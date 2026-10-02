# typed: strict
# frozen_string_literal: true

module Services
  module Inbound
    # Backfills a channel's history after a reconnect. The checkpoint advances
    # only through revisions this snapshot covered. Permanent rejections are
    # quarantined idempotently; transport failures propagate for retry.
    # Task 4 replaces the raw chat_checkpoints access.
    class HistoryRecovery
      extend T::Sig

      Post = Adapters::Mattermost::Dto::Post
      Entry = Adapters::Mattermost::Dto::HistoryEntry
      UPSTREAM_CAP = 1000

      sig do
        params(db: Sequel::Database, api: Adapters::Mattermost::Api, verifier: Adapters::Mattermost::DeliveryVerifier,
               router: Domains::Mattermost::Router).void
      end
      def initialize(db, api:, verifier:, router:)
        @db = T.let(db, Sequel::Database)
        @api = T.let(api, Adapters::Mattermost::Api)
        @verifier = T.let(verifier, Adapters::Mattermost::DeliveryVerifier)
        @router = T.let(router, Domains::Mattermost::Router)
      end

      sig { params(channel_id: String).returns(Integer) }
      def call(channel_id:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          @verifier.identifier!(channel_id)
          checkpoint = checkpoint_for(channel_id)
          # The pinned positive-since query caps its unordered result at 1000.
          # A full cap is ambiguous: stop without advancing the checkpoint.
          since = [checkpoint - UPSTREAM_CAP, 0].max
          page_number = 0
          latest = checkpoint
          loop do
            history = history_page(channel_id, since, page_number)
            if since.positive? && (history.entries.size >= UPSTREAM_CAP || history.order.size >= UPSTREAM_CAP)
              raise RecoveryRequired, "History reached upstream 1000-post cap; checkpoint retained; operator recovery required"
            end

            verified_history(history, channel_id).each do |entry, post, covered_revision|
              begin
                delivery = @verifier.delivery(post_id: post.id, channel_id: channel_id, event_kind: event_kind(post))
              rescue ArgumentError => error
                quarantine(channel_id, entry, error.message)
                next
              end
              @router.ingest(delivery: delivery)
              # REST refetch may see a later edit than this history snapshot.
              # That edit cannot prove intervening posts were covered here.
              latest = [latest, covered_revision].max
            end
            break unless since.zero? && history.order.size == Adapters::Mattermost::Api::HISTORY_PAGE_SIZE

            page_number += 1
          end
          advance_checkpoint(channel_id, latest)
          latest
        end
      end

      private

      sig { params(channel_id: String).returns(Integer) }
      def checkpoint_for(channel_id)
        row = @db[:chat_checkpoints][channel_id: channel_id]
        return 0 unless row.is_a?(Hash)

        value = row[:post_revision]
        raise IOError, "Malformed chat checkpoint" unless value.is_a?(Integer) && value >= 0

        value
      end

      sig { params(channel_id: String, since: Integer, page_number: Integer).returns(Adapters::Mattermost::Dto::HistoryPage) }
      def history_page(channel_id, since, page_number)
        page = @api.channel_history(channel_id: channel_id, since: since, page: since.zero? ? page_number : nil)
        keys = page.entries.map(&:key)
        raise Adapters::Mattermost::Errors::RequestFailed, Adapters::Mattermost::Api::MALFORMED_ENVELOPE unless page.order.all? { |id| keys.include?(id) }

        page
      end

      sig { params(page: Adapters::Mattermost::Dto::HistoryPage, channel_id: String).returns(T::Array[[Entry, Post, Integer]]) }
      def verified_history(page, channel_id)
        posts = T.let([], T::Array[[Entry, Post, Integer]])
        page.entries.each do |entry|
          post = entry.post
          reason = entry.rejection || rejection(entry, post, channel_id)
          if post && reason.nil?
            posts << [entry, post, @verifier.revision(post)]
          else
            quarantine(channel_id, entry, reason || Adapters::Mattermost::Api::MALFORMED_HISTORY_POST)
          end
        end
        posts.sort_by { |_entry, post, revision| [revision, post.id] }
      end

      sig { params(entry: Entry, post: T.nilable(Post), channel_id: String).returns(T.nilable(String)) }
      def rejection(entry, post, channel_id)
        return Adapters::Mattermost::Api::MALFORMED_HISTORY_POST unless post
        return "History identity mismatch" unless post.id == entry.key
        return "History channel mismatch" unless post.channel_id == channel_id

        @verifier.identifier!(post.id)
        nil
      rescue ArgumentError => error
        error.message
      end

      sig { params(post: Post).returns(String) }
      def event_kind(post)
        return "post_deleted" if post.delete_at.positive?

        post.update_at > post.create_at ? "post_edited" : "posted"
      end

      sig { params(channel_id: String, revision: Integer).void }
      def advance_checkpoint(channel_id, revision)
        @db[:chat_checkpoints].insert_conflict(
          target: :channel_id,
          update: { post_revision: Sequel.function(:greatest, Sequel[:chat_checkpoints][:post_revision], revision) }
        ).insert(channel_id: channel_id, post_revision: revision)
      end

      # The digest equals SHA256(JSON.generate([channel_id, post])) over the
      # post as received, so event keys match pre-refactor receipts.
      sig { params(channel_id: String, entry: Entry, reason: String).void }
      def quarantine(channel_id, entry, reason)
        digest = Digest::SHA256.hexdigest("[#{JSON.generate(channel_id)},#{entry.canonical_json}]")
        raw_id = entry.post_id
        post_id = raw_id&.match?(Adapters::Mattermost::Api::IDENTIFIER) ? raw_id : nil
        Platform::Audit::Log.new.record_once(event_key: "history-rejected:#{digest}", action: "history_rejected", channel_id: channel_id,
                                             post_id: post_id, details: Domains::Mattermost::Dto::HistoryRejectedAudit.new(reason: reason))
      end
    end
  end
end
