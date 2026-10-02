# typed: strict
# frozen_string_literal: true

require "digest"
require "uri"

module Domains
  module Mattermost
    class Reconcile
      extend T::Sig

      class RecoveryRequired < Client::Error; end

      HistoryPost = T.type_alias { VerifiedDelivery::TransportResponse }

      class HistoryPage < T::Struct
        const :posts, T::Hash[String, HistoryPost]
        const :order, T::Array[String]
      end

      # History reconciliation only needs authenticated, validated GET responses.
      # Keep that boundary explicit so callers cannot smuggle an arbitrary object
      # through the reconciliation path.
      sig { params(db: Sequel::Database, client: VerifiedDelivery::Transport, resolver: ActorResolver, router: Router).void }
      def initialize(db, client:, resolver:, router:)
        @db = T.let(db, Sequel::Database)
        @client = T.let(client, VerifiedDelivery::Transport)
        @resolver = T.let(resolver, ActorResolver)
        @router = T.let(router, Router)
      end

      sig { params(channel_id: String).returns(Integer) }
      def channel(channel_id)
        @resolver.identifier!(channel_id)
        checkpoint = checkpoint_for(channel_id)
        # The pinned positive-since query caps its unordered result at 1000.
        # A full cap is ambiguous: stop without advancing the checkpoint.
        since = [checkpoint - 1000, 0].max
        page_number = 0
        latest = checkpoint
        loop do
          history = history_page(channel_id, since, page_number)
          if since.positive? && [history.posts.size, history.order.size].max >= 1000
            raise RecoveryRequired, "History reached upstream 1000-post cap; checkpoint retained; operator recovery required"
          end

          verified_history(history, channel_id).each do |post, covered_revision|
            kind = event_kind(post)
            begin
              delivery = @resolver.delivery(post_id: string_value(post, "id"), channel_id: channel_id, event_kind: kind)
            rescue ArgumentError => error
              quarantine(channel_id, post, error)
              next
            end
            @router.ingest(delivery: delivery)
            # REST refetch may see a later edit than this history snapshot.
            # That edit cannot prove intervening posts were covered here.
            latest = [latest, covered_revision].max
          end
          break unless since.zero? && history.order.size == 200

          page_number += 1
        end
        advance_checkpoint(channel_id, latest)
        latest
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

      sig { params(channel_id: String, since: Integer, page_number: Integer).returns(HistoryPage) }
      def history_page(channel_id, since, page_number)
        params = T.let({ since: since, collapsedThreads: "false" }, T::Hash[Symbol, T.any(Integer, String)])
        if since.zero?
          params[:page] = page_number
          params[:per_page] = 200
        end
        path = "/api/v4/channels/#{channel_id}/posts?#{URI.encode_www_form(params)}"
        page = parse_history_page(@client.get(path))
        raise Client::Error, "Malformed history envelope; checkpoint retained" unless page.order.all? { |id| page.posts.key?(id) }

        page
      end

      sig { params(value: Object).returns(HistoryPage) }
      def parse_history_page(value)
        raise Client::Error, "Malformed history envelope; checkpoint retained" unless value.is_a?(Hash)

        posts_value = value["posts"]
        order_value = value["order"]
        raise Client::Error, "Malformed history envelope; checkpoint retained" unless posts_value.is_a?(Hash) && order_value.is_a?(Array)

        posts = T.let({}, T::Hash[String, HistoryPost])
        posts_value.each do |id, post|
          raise Client::Error, "Malformed history envelope; checkpoint retained" unless id.is_a?(String)

          posts[id] = transport_post(post)
        end
        order = T.let([], T::Array[String])
        order_value.each do |id|
          raise Client::Error, "Malformed history envelope; checkpoint retained" unless id.is_a?(String)

          order << id
        end
        HistoryPage.new(posts: posts, order: order)
      end

      sig { params(value: Object).returns(HistoryPost) }
      def transport_post(value)
        raise Client::Error, "Malformed history envelope; checkpoint retained" unless value.is_a?(Hash)

        post = T.let({}, HistoryPost)
        value.each do |key, item|
          raise Client::Error, "Malformed history envelope; checkpoint retained" unless key.is_a?(String) && transport_value?(item)

          post[key] = item
        end
        post
      end

      sig { params(value: Object).returns(T::Boolean) }
      def transport_value?(value)
        value.is_a?(String) || value.is_a?(Integer) || value == true || value == false || value.nil?
      end

      sig { params(page: HistoryPage, channel_id: String).returns(T::Array[[HistoryPost, Integer]]) }
      def verified_history(page, channel_id)
        posts = T.let([], T::Array[[HistoryPost, Integer]])
        page.posts.each do |id, post|
          begin
            raise ArgumentError, "History identity mismatch" unless string_value(post, "id") == id
            raise ArgumentError, "History channel mismatch" unless string_value(post, "channel_id") == channel_id

            @resolver.identifier!(id)
            posts << [post, @resolver.revision(post_value(post))]
          rescue ArgumentError, KeyError, TypeError => error
            quarantine(channel_id, post, error)
          end
        end
        posts.sort_by { |post, revision| [revision, string_value(post, "id")] }
      end

      sig { params(post: HistoryPost).returns(VerifiedDelivery::Post) }
      def post_value(post)
        VerifiedDelivery::Post.new(id: string_value(post, "id"), channel_id: string_value(post, "channel_id"),
                                   user_id: string_value(post, "user_id"), root_id: optional_string_value(post, "root_id"),
                                   message: string_value(post, "message"), create_at: non_negative_integer(post, "create_at"),
                                   update_at: non_negative_integer(post, "update_at"), delete_at: non_negative_integer(post, "delete_at"))
      end

      sig { params(post: HistoryPost).returns(String) }
      def event_kind(post)
        delete_at = non_negative_integer(post, "delete_at")
        return "post_deleted" if delete_at.positive?

        non_negative_integer(post, "update_at") > non_negative_integer(post, "create_at") ? "post_edited" : "posted"
      end

      sig { params(channel_id: String, revision: Integer).void }
      def advance_checkpoint(channel_id, revision)
        @db[:chat_checkpoints].insert_conflict(
          target: :channel_id,
          update: { post_revision: Sequel.function(:greatest, Sequel[:chat_checkpoints][:post_revision], revision) }
        ).insert(channel_id: channel_id, post_revision: revision)
      end

      sig { params(channel_id: String, post: Object, error: StandardError).void }
      def quarantine(channel_id, post, error)
        digest = Digest::SHA256.hexdigest(JSON.generate([channel_id, post]))
        post_id = post.is_a?(Hash) && post["id"].is_a?(String) && post["id"].match?(/\A[a-z0-9]{26}\z/) ? post["id"] : nil
        @db[:audit].insert_conflict(target: :event_key).insert(
          event_key: "history-rejected:#{digest}", action: "history_rejected", channel_id: channel_id,
          post_id: post_id, details: Sequel.pg_jsonb({ reason: error.message })
        )
      end

      sig { params(post: HistoryPost, key: String).returns(String) }
      def string_value(post, key)
        value = post.fetch(key)
        raise ArgumentError, "Malformed history post" unless value.is_a?(String)

        value
      end

      sig { params(post: HistoryPost, key: String).returns(T.nilable(String)) }
      def optional_string_value(post, key)
        value = post[key]
        raise ArgumentError, "Malformed history post" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(post: HistoryPost, key: String).returns(Integer) }
      def non_negative_integer(post, key)
        value = post.fetch(key)
        raise ArgumentError, "Malformed history post" unless value.is_a?(Integer) && value >= 0

        value
      end
    end
  end
end
