# frozen_string_literal: true

module Domains
  module Mattermost
    class ActorResolver
      KINDS = %w[posted post_edited post_deleted].freeze
      def initialize(client, local_bot_ids: [], peer_bot_ids: [])
        @client, @local, @peers = client, local_bot_ids, peer_bot_ids
      end

      def event(envelope)
        kind = envelope.fetch("event")
        raise ArgumentError, "Unsupported event" unless KINDS.include?(kind)

        candidate = JSON.parse(envelope.fetch("data").fetch("post"))
        broadcast = envelope.fetch("broadcast", {})["channel_id"]
        raise ArgumentError, "Event channel mismatch" if broadcast && broadcast != candidate["channel_id"]

        delivery(post_id: candidate.fetch("id"), channel_id: candidate.fetch("channel_id"), event_kind: kind)
      end

      def delivery(post_id:, channel_id:, event_kind:)
        identifier!(post_id); identifier!(channel_id)
        raise ArgumentError, "Unsupported event" unless KINDS.include?(event_kind)

        post = @client.get("/api/v4/posts/#{post_id}")
        raise ArgumentError, "Post/channel mismatch" unless post["id"] == post_id && post["channel_id"] == channel_id

        sender = identifier!(post.fetch("user_id"))
        thread = identifier!(post["root_id"].to_s.empty? ? post_id : post["root_id"])
        root = thread == post_id ? post : @client.get("/api/v4/posts/#{thread}")
        raise ArgumentError,
              "Cross-channel or non-root thread" unless root["id"] == thread && root["channel_id"] == channel_id && root["root_id"].to_s.empty?

        revision = revision!(post)
        revision!(root)
        raise ArgumentError, "Deleted thread root" unless root["delete_at"].zero?
        raise ArgumentError, "Deleted post" if event_kind != "post_deleted" && !post["delete_at"].zero?

        channel = @client.get("/api/v4/channels/#{channel_id}")
        raise ArgumentError, "Channel identity mismatch" unless channel["id"] == channel_id

        member = @client.get("/api/v4/channels/#{channel_id}/members/#{sender}")
        raise ArgumentError,
              "Revoked membership" unless member["channel_id"] == channel_id && member["user_id"] == sender

        user = @client.get("/api/v4/users/#{sender}")
        raise ArgumentError, "Unverified sender" unless user["id"] == sender && user.fetch("delete_at", 0) == 0

        # v11.11.1 omits false in authenticated User.IsBot JSON; never derive
        # this default from WS candidate fields or model-supplied context.
        bot = user.fetch("is_bot", false)
        raise ArgumentError, "Unverified bot status" unless bot == true || bot == false
        raise ArgumentError, "Own bot loop" if @local.include?(sender)

        actor = Domains::Workflows::Entities::Actor.new(user_id: sender, channel_id: channel_id, member: true,
                                                        bot: bot || @peers.include?(sender))
        VerifiedDelivery.new(channel_id: channel_id, post_id: post_id, thread_id: thread, actor: actor,
                             event_kind: event_kind, post_revision: revision, body: post.fetch("message"), root_post: post_id == thread)
      rescue KeyError, JSON::ParserError, TypeError => e
        raise ArgumentError, "Malformed server delivery (#{e.class})"
      end

      def revision!(post)
        values = %w[create_at update_at delete_at].map { |key| post.fetch(key) }
        raise ArgumentError, "Invalid post revision" unless values.all? { |v| v.is_a?(Integer) && v >= 0 }

        values.max
      end

      def identifier!(value)
        raise ArgumentError,
              "Invalid Mattermost identifier" unless value.is_a?(String) && value.match?(/\A[a-z0-9]{26}\z/)

        value
      end
    end
  end
end
