# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class Delivery
      extend T::Sig

      PostPayload = T.type_alias { T::Hash[String, T.any(String, T::Hash[String, String])] }
      ResponseValue = T.type_alias { T.any(String, Integer, T::Boolean, NilClass, T::Hash[String, String]) }
      Response = T.type_alias { T::Hash[String, ResponseValue] }
      PostList = T.type_alias { T::Hash[String, Response] }
      GetResponse = T.type_alias { T.any(Response, T::Hash[String, PostList]) }
      # Outbox rows include persisted status metadata such as retry counts and
      # database timestamps in addition to the string delivery identity.
      RowValue = T.type_alias { T.any(String, Integer, Time, DateTime, NilClass) }
      Row = T.type_alias { T::Hash[Symbol, RowValue] }

      module Transport
        extend T::Helpers
        extend T::Sig

        interface!

        sig { abstract.params(path: String).returns(GetResponse) }
        def get(path); end

        sig { abstract.params(path: String, body: PostPayload).returns(Response) }
        def post(path, body); end
      end

      class ClientTransport
        include Transport
        extend T::Sig

        sig { params(client: Client).void }
        def initialize(client)
          @client = T.let(client, Client)
        end

        sig { override.params(path: String).returns(GetResponse) }
        def get(path)
          raw = T.let(@client.get(path), Object)
          return post_list_response(raw) if raw.is_a?(Hash) && raw.key?("posts")

          response(raw)
        end

        sig { override.params(path: String, body: PostPayload).returns(Response) }
        def post(path, body)
          response(@client.post(path, body))
        end

        private

        sig { params(value: Object).returns(Response) }
        def response(value)
          raise ArgumentError, "Malformed Mattermost response" unless value.is_a?(Hash)

          response = T.let({}, Response)
          value.each do |key, item|
            raise ArgumentError, "Malformed Mattermost response" unless key.is_a?(String) && response_value?(item)

            response[key] = item
          end
          response
        end

        sig { params(value: Object).returns(T::Boolean) }
        def response_value?(value)
          value.is_a?(String) || value.is_a?(Integer) || value == true || value == false || value.nil? ||
            (value.is_a?(Hash) && value.all? { |key, item| key.is_a?(String) && item.is_a?(String) })
        end

        sig { params(value: Object).returns(T::Hash[String, PostList]) }
        def post_list_response(value)
          raise ArgumentError, "Malformed Mattermost post list" unless value.is_a?(Hash)

          posts = value.fetch("posts")
          raise ArgumentError, "Malformed Mattermost post list" unless posts.is_a?(Hash)

          list = T.let({}, PostList)
          posts.each do |id, post|
            raise ArgumentError, "Malformed Mattermost post list" unless id.is_a?(String)

            list[id] = response(post)
          end
          { "posts" => list }
        end
      end

      class OutboxItem < T::Struct
        const :id, String
        const :status, String
        const :bot, String
        const :channel_id, String
        const :thread_id, T.nilable(String)
        const :body, String
        const :response_key, String
        const :created_at, Time
      end

      sig { params(db: Sequel::Database).returns(Delivery) }
      def self.from_env(db)
        url = ENV.fetch("MATTERMOST_URL")
        clients = T.let({}, T::Hash[String, Transport])
        ids = T.let({}, T::Hash[String, String])
        %w[worker agent].each do |role|
          clients[role] = ClientTransport.new(Client.new(url: url, token_file: ENV.fetch("MATTERMOST_#{role.upcase}_TOKEN_FILE")))
          ids[role] = ENV.fetch("MATTERMOST_#{role.upcase}_BOT_ID")
        end
        new(db, clients: clients, bot_ids: ids)
      end

      sig { params(db: Sequel::Database, clients: T::Hash[String, Transport], bot_ids: T::Hash[String, String]).void }
      def initialize(db, clients:, bot_ids:)
        @db = T.let(db, Sequel::Database)
        @clients = T.let(clients, T::Hash[String, Transport])
        @bot_ids = T.let(bot_ids, T::Hash[String, String])
      end

      sig { params(job: Domains::Jobs::Job, jobs: Domains::Jobs::Store).void }
      def call(job, jobs)
        row = outbox_item(@db[:outbox][id: job_payload(job).fetch("outbox_id")])
        raise ArgumentError, "Unknown outbox item" unless row
        return if row.status == "delivered"

        raise "Outbox requires reconciliation" unless row.status == "pending"

        client = @clients.fetch(row.bot)
        bot = @bot_ids.fetch(row.bot)
        verify_destination!(client, row, bot)
        @db.transaction do
          raise "Lost external effect lease" unless jobs.begin_effect(id: job_string(job, :id), lease_token: job_string(job, :lease_token))

          @db[:outbox].where(id: row.id).update(status: "uncertain")
        end
        remote = client.post("/api/v4/posts", post_payload(row))
        verify_result!(remote, row, bot)
        @db[:outbox].where(id: row.id).update(status: "delivered", remote_post_id: string_value(remote, "id"))
      end

      sig { params(outbox_id: String).returns(T::Boolean) }
      def reconcile(outbox_id:)
        row = outbox_item(@db[:outbox][id: outbox_id])
        raise ArgumentError, "Expected uncertain delivery" unless row && row.status == "uncertain"

        client = @clients.fetch(row.bot)
        bot = @bot_ids.fetch(row.bot)
        verify_destination!(client, row, bot)
        since = [(row.created_at.to_f * 1000).to_i - 1000, 1].max
        matches = post_list(client.get("/api/v4/channels/#{row.channel_id}/posts?since=#{since}&collapsedThreads=false")).values.select do |post|
          props(post)["digitaltwin_response_key"] == row.response_key
        end
        return false unless matches.size == 1

        post = matches.fetch(0)
        verify_result!(post, row, bot)
        @db.transaction do
          @db[:outbox].where(id: row.id, status: "uncertain").update(status: "delivered", remote_post_id: string_value(post, "id"))
          @db[:jobs].where(dispatch_key: "outbox:#{row.id}", status: "uncertain").update(status: "complete", lease_token: nil, lease_expires_at: nil)
        end
        true
      end

      private

      sig { params(client: Transport, row: OutboxItem, bot: String).void }
      def verify_destination!(client, row, bot)
        [row.channel_id, bot, row.thread_id].compact.each { |identifier| identifier!(identifier) }
        me = response(client.get("/api/v4/users/me"))
        raise ArgumentError, "Wrong bot identity" unless string_value(me, "id") == bot && boolean_value(me, "is_bot")

        channel = response(client.get("/api/v4/channels/#{row.channel_id}"))
        member = response(client.get("/api/v4/channels/#{row.channel_id}/members/#{bot}"))
        valid_membership = [string_value(channel, "id") == row.channel_id,
                            string_value(member, "channel_id") == row.channel_id,
                            string_value(member, "user_id") == bot].all?
        raise ArgumentError, "Bot/channel membership mismatch" unless valid_membership
        return unless row.thread_id

        root = response(client.get("/api/v4/posts/#{row.thread_id}"))
        valid_root = [string_value(root, "id") == row.thread_id,
                      string_value(root, "channel_id") == row.channel_id,
                      optional_string_value(root, "root_id").to_s.empty?,
                      integer_value(root, "delete_at").zero?].all?
        raise ArgumentError, "Invalid source thread" unless valid_root
      end

      sig { params(post: Response, row: OutboxItem, bot: String).void }
      def verify_result!(post, row, bot)
        verified = [identifier?(string_value(post, "id")),
                    string_value(post, "channel_id") == row.channel_id,
                    optional_string_value(post, "root_id").to_s == row.thread_id.to_s,
                    string_value(post, "user_id") == bot,
                    string_value(post, "message") == row.body].all?
        raise "Unverified Mattermost delivery result" unless verified
      end

      sig { params(row: OutboxItem).returns(PostPayload) }
      def post_payload(row)
        { "channel_id" => row.channel_id, "root_id" => row.thread_id || "", "message" => row.body,
          "props" => { "digitaltwin_response_key" => row.response_key } }
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

      sig { params(value: Object).returns(Response) }
      def response(value)
        raise ArgumentError, "Malformed Mattermost response" unless value.is_a?(Hash)

        response = T.let({}, Response)
        value.each do |key, item|
          raise ArgumentError, "Malformed Mattermost response" unless key.is_a?(String) && response_value?(item)

          response[key] = item
        end
        response
      end

      sig { params(value: Object).returns(T::Boolean) }
      def response_value?(value)
        value.is_a?(String) || value.is_a?(Integer) || value == true || value == false || value.nil? ||
          (value.is_a?(Hash) && value.all? { |key, item| key.is_a?(String) && item.is_a?(String) })
      end

      sig { params(value: GetResponse).returns(PostList) }
      def post_list(value)
        posts = value["posts"]
        raise ArgumentError, "Malformed Mattermost post list" unless posts.is_a?(Hash)

        list = T.let({}, PostList)
        posts.each do |id, post|
          raise ArgumentError, "Malformed Mattermost post list" unless id.is_a?(String)

          list[id] = response(post)
        end
        list
      end

      sig { params(response: Response, key: String).returns(String) }
      def string_value(response, key)
        value = response.fetch(key)
        raise ArgumentError, "Malformed Mattermost response" unless value.is_a?(String)

        value
      end

      sig { params(response: Response, key: String).returns(T.nilable(String)) }
      def optional_string_value(response, key)
        value = response[key]
        raise ArgumentError, "Malformed Mattermost response" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(response: Response, key: String).returns(Integer) }
      def integer_value(response, key)
        value = response.fetch(key)
        raise ArgumentError, "Malformed Mattermost response" unless value.is_a?(Integer)

        value
      end

      sig { params(response: Response, key: String).returns(T::Boolean) }
      def boolean_value(response, key)
        value = response.fetch(key)
        raise ArgumentError, "Malformed Mattermost response" unless value == true || value == false

        value
      end

      sig { params(response: Response).returns(T::Hash[String, String]) }
      def props(response)
        value = response["props"]
        return {} if value.nil?

        raise ArgumentError, "Malformed Mattermost post props" unless value.is_a?(Hash)

        value
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
        value.match?(/\A[a-z0-9]{26}\z/)
      end

      sig { params(job: Domains::Jobs::Job).returns(T::Hash[String, String]) }
      def job_payload(job)
        value = job.payload
        payload = T.let({}, T::Hash[String, String])
        value.each do |key, item|
          raise ArgumentError, "Malformed delivery job" unless item.is_a?(String)

          payload[key] = item
        end
        payload
      end

      sig { params(job: Domains::Jobs::Job, key: Symbol).returns(String) }
      def job_string(job, key)
        return job.id if key == :id

        token = job.lease_token
        return token if key == :lease_token && token

        raise ArgumentError, "Malformed delivery job"
      end
    end
  end
end
