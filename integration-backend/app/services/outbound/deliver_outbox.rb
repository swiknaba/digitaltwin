# typed: strict
# frozen_string_literal: true

module Services
  module Outbound
    # Delivers one outbox row as the configured bot after verifying identity,
    # membership, and thread root. An unknown post result stays uncertain and
    # is never retried; `reconcile` settles it only from server evidence.
    # Task 4 replaces the raw outbox access.
    class DeliverOutbox
      extend T::Sig

      Api = Adapters::Mattermost::Api
      # Outbox rows include persisted status metadata such as retry counts and
      # database timestamps in addition to the string delivery identity.
      RowValue = T.type_alias { T.any(String, Integer, Time, DateTime, NilClass) }
      Row = T.type_alias { T::Hash[Symbol, RowValue] }

      sig { params(db: Sequel::Database).returns(DeliverOutbox) }
      def self.from_env(db)
        url = ENV.fetch("MATTERMOST_URL")
        apis = T.let({}, T::Hash[String, Api])
        ids = T.let({}, T::Hash[String, String])
        %w[worker agent].each do |role|
          apis[role] = Api.new(client: Adapters::Mattermost::Client.new(url: url, token_file: ENV.fetch("MATTERMOST_#{role.upcase}_TOKEN_FILE")))
          ids[role] = ENV.fetch("MATTERMOST_#{role.upcase}_BOT_ID")
        end
        new(db, apis: apis, bot_ids: ids)
      end

      sig { params(db: Sequel::Database, apis: T::Hash[String, Api], bot_ids: T::Hash[String, String]).void }
      def initialize(db, apis:, bot_ids:)
        @db = T.let(db, Sequel::Database)
        @apis = T.let(apis, T::Hash[String, Api])
        @bot_ids = T.let(bot_ids, T::Hash[String, String])
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          payload = Domains::Mattermost::Dto::OutboxPostJob.from_hash(job.payload, true)
          row = outbox_item(@db[:outbox][id: payload.outbox_id])
          raise ArgumentError, "Unknown outbox item" unless row
          next Platform::Jobs::Dto::Decision.complete if row.status == "delivered"

          raise "Outbox requires reconciliation" unless row.status == "pending"

          api = @apis.fetch(row.bot)
          bot = @bot_ids.fetch(row.bot)
          verify_destination!(api, row, bot)
          @db.transaction do
            raise "Lost external effect lease" unless job.lease.begin_effect

            @db[:outbox].where(id: row.id).update(status: "uncertain")
          end
          remote = api.create_post(Adapters::Mattermost::Dto::NewPost.new(channel_id: row.channel_id, root_id: row.thread_id || "", message: row.body,
                                                                          props: { "digitaltwin_response_key" => row.response_key }))
          verify_result!(remote, row, bot)
          @db[:outbox].where(id: row.id).update(status: "delivered", remote_post_id: remote.id)
          Platform::Jobs::Dto::Decision.complete
        end
      end

      sig { params(outbox_id: String).returns(T::Boolean) }
      def reconcile(outbox_id:)
        row = outbox_item(@db[:outbox][id: outbox_id])
        raise ArgumentError, "Expected uncertain delivery" unless row && row.status == "uncertain"

        api = @apis.fetch(row.bot)
        bot = @bot_ids.fetch(row.bot)
        verify_destination!(api, row, bot)
        since = [(row.created_at.to_f * 1000).to_i - 1000, 1].max
        history = api.channel_history(channel_id: row.channel_id, since: since, page: nil)
        raise ArgumentError, "Malformed Mattermost post list" unless history.entries.all?(&:post)

        matches = history.entries.filter_map(&:post).select { |post| post.props["digitaltwin_response_key"] == row.response_key }
        return false unless matches.size == 1

        post = matches.fetch(0)
        verify_result!(post, row, bot)
        @db.transaction do
          @db[:outbox].where(id: row.id, status: "uncertain").update(status: "delivered", remote_post_id: post.id)
          jobs = Platform::Jobs::Store.new
          job = jobs.find_by_key(dispatch_key: "outbox:#{row.id}")
          jobs.close_uncertain(id: job.id) if job
        end
        true
      end

      private

      sig { params(api: Api, row: OutboxItem, bot: String).void }
      def verify_destination!(api, row, bot)
        [row.channel_id, bot, row.thread_id].compact.each { |identifier| identifier!(identifier) }
        me = api.me
        raise ArgumentError, "Wrong bot identity" unless me.id == bot && me.bot

        channel = api.channel(row.channel_id)
        member = api.member(channel_id: row.channel_id, user_id: bot)
        valid_membership = [channel.id == row.channel_id, member&.channel_id == row.channel_id, member&.user_id == bot].all?
        raise ArgumentError, "Bot/channel membership mismatch" unless valid_membership

        thread_id = row.thread_id
        return unless thread_id

        root = api.post(thread_id)
        valid_root = [root.id == thread_id, root.channel_id == row.channel_id, root.root_id.to_s.empty?, root.delete_at.zero?].all?
        raise ArgumentError, "Invalid source thread" unless valid_root
      end

      sig { params(post: Adapters::Mattermost::Dto::Post, row: OutboxItem, bot: String).void }
      def verify_result!(post, row, bot)
        verified = [identifier?(post.id), post.channel_id == row.channel_id, post.root_id.to_s == row.thread_id.to_s,
                    post.user_id == bot, post.message == row.body].all?
        raise "Unverified Mattermost delivery result" unless verified
      end

      sig { params(value: Object).returns(T.nilable(OutboxItem)) }
      def outbox_item(value)
        return nil unless value.is_a?(Hash)

        row = row_from(value)
        OutboxItem.new(id: row_string(row, :id), status: row_string(row, :status), bot: row_string(row, :bot), channel_id: row_string(row, :channel_id),
                       thread_id: optional_row_string(row, :thread_id), body: row_string(row, :body), response_key: row_string(row, :response_key),
                       created_at: row_time(row, :created_at))
      end

      sig { params(value: Object).returns(Row) }
      def row_from(value)
        raise ArgumentError, "Malformed outbox item" unless value.is_a?(Hash)

        row = T.let({}, Row)
        value.each do |key, item|
          valid_value = item.is_a?(String) || item.is_a?(Integer) || item.is_a?(Time) || item.is_a?(DateTime) || item.nil?
          raise ArgumentError, "Malformed outbox item" unless key.is_a?(Symbol) && valid_value

          row[key] = item
        end
        row
      end

      sig { params(row: Row, key: Symbol).returns(String) }
      def row_string(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Malformed outbox item" unless value.is_a?(String)

        value
      end

      sig { params(row: Row, key: Symbol).returns(T.nilable(String)) }
      def optional_row_string(row, key)
        value = row[key]
        raise ArgumentError, "Malformed outbox item" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(row: Row, key: Symbol).returns(Time) }
      def row_time(row, key)
        value = row.fetch(key)
        return value if value.is_a?(Time)
        return value.to_time if value.is_a?(DateTime)

        raise ArgumentError, "Malformed outbox item"
      end

      sig { params(value: String).returns(String) }
      def identifier!(value)
        raise ArgumentError, "Invalid Mattermost destination ID" unless identifier?(value)

        value
      end

      sig { params(value: String).returns(T::Boolean) }
      def identifier?(value)
        value.match?(Api::IDENTIFIER)
      end
    end
  end
end
