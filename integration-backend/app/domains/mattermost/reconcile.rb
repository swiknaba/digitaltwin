# frozen_string_literal: true

require "uri"
module Domains
  module Mattermost
    class Reconcile
      def initialize(db, client:, resolver:, router:)
        @db, @client, @resolver, @router = db, client, resolver, router
      end

      def channel(channel_id)
        @resolver.identifier!(channel_id)
        checkpoint = @db[:chat_checkpoints][channel_id: channel_id]&.fetch(:post_revision) || 0
        # Positive since path supplies all updated posts; zero uses page/per_page.
        since = [checkpoint - 1000, 0].max
        page = 0
        latest = checkpoint
        loop do
          params = { since: since, collapsedThreads: "false" }
          params.merge!(page: page, per_page: 200) if since.zero?
          list = @client.get("/api/v4/channels/#{channel_id}/posts?#{URI.encode_www_form(params)}")
          posts = list.fetch("posts").values.sort_by { |post| [@resolver.revision!(post), post.fetch("id")] }
          posts.each do |post|
            raise ArgumentError, "History channel mismatch" unless post["channel_id"] == channel_id

            kind = post["delete_at"].positive? ? "post_deleted" : (post["update_at"] > post["create_at"] ? "post_edited" : "posted")
            delivery = @resolver.delivery(post_id: post.fetch("id"), channel_id: channel_id, event_kind: kind)
            @router.ingest(delivery: delivery)
            latest = [latest, delivery.post_revision].max
          end
          break unless since.zero? && list.fetch("order").size == 200

          page += 1
        end
        @db[:chat_checkpoints].insert_conflict(target: :channel_id, update: { post_revision: Sequel.function(:greatest, Sequel[:chat_checkpoints][:post_revision], latest) }).insert(
          channel_id: channel_id, post_revision: latest
        )
        latest
      end
    end
  end
end
