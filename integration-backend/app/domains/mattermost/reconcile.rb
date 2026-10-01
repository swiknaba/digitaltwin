# frozen_string_literal: true

require "uri"
require "digest"
module Domains
  module Mattermost
    class Reconcile
      class RecoveryRequired < Client::Error; end

      def initialize(db, client:, resolver:, router:)
        @db, @client, @resolver, @router = db, client, resolver, router
      end

      def channel(channel_id)
        @resolver.identifier!(channel_id)
        checkpoint = @db[:chat_checkpoints][channel_id: channel_id]&.fetch(:post_revision) || 0
        # The pinned positive-since query caps its unordered result at 1000.
        # A full cap is ambiguous: stop without advancing the checkpoint.
        since = [checkpoint - 1000, 0].max
        page = 0
        latest = checkpoint
        loop do
          params = { since: since, collapsedThreads: "false" }
          params.merge!(page: page, per_page: 200) if since.zero?
          list = @client.get("/api/v4/channels/#{channel_id}/posts?#{URI.encode_www_form(params)}")
          unless list.is_a?(Hash) && list["posts"].is_a?(Hash) && list["order"].is_a?(Array) &&
                 list["order"].all? { |id| list["posts"].key?(id) }
            raise Client::Error, "Malformed history envelope; checkpoint retained"
          end
          if since.positive? && [list["posts"].size, list["order"].size].max >= 1000
            raise RecoveryRequired, "History reached upstream 1000-post cap; checkpoint retained; operator recovery required"
          end

          posts = list["posts"].filter_map do |id, post|
            begin
              raise ArgumentError, "History identity mismatch" unless post.is_a?(Hash) && post["id"] == id

              @resolver.identifier!(id)
              raise ArgumentError, "History channel mismatch" unless post["channel_id"] == channel_id

              [post, @resolver.revision!(post)]
            rescue ArgumentError, KeyError, TypeError => error
              quarantine(channel_id, post, error)
              nil
            end
          end.sort_by { |post, revision| [revision, post["id"]] }
          posts.each do |post, covered_revision|
            kind = post["delete_at"].positive? ? "post_deleted" : (post["update_at"] > post["create_at"] ? "post_edited" : "posted")
            begin
              delivery = @resolver.delivery(post_id: post.fetch("id"), channel_id: channel_id, event_kind: kind)
            rescue ArgumentError => error
              quarantine(channel_id, post, error)
              next
            end
            @router.ingest(delivery: delivery)
            # REST refetch may see a later edit than this history snapshot.
            # That edit cannot prove intervening posts were covered here.
            latest = [latest, covered_revision].max
          end
          break unless since.zero? && list.fetch("order").size == 200

          page += 1
        end
        @db[:chat_checkpoints].insert_conflict(target: :channel_id, update: { post_revision: Sequel.function(:greatest, Sequel[:chat_checkpoints][:post_revision], latest) }).insert(
          channel_id: channel_id, post_revision: latest
        )
        latest
      end

      private

      def quarantine(channel_id, post, error)
        digest = Digest::SHA256.hexdigest(JSON.generate([channel_id, post]))
        id = post.is_a?(Hash) && post["id"].is_a?(String) && post["id"].match?(/\A[a-z0-9]{26}\z/) ? post["id"] : nil
        @db[:audit].insert_conflict(target: :event_key).insert(
          event_key: "history-rejected:#{digest}", action: "history_rejected", channel_id: channel_id,
          post_id: id, details: Sequel.pg_jsonb({ reason: error.message })
        )
      end
    end
  end
end
