# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class ActorResolver
      extend T::Sig
      include Domains::Commander::Source::DeliveryResolver

      KINDS = T.let(["posted", "post_edited", "post_deleted"].freeze, T::Array[String])
      EventValue = T.type_alias { T.any(String, Integer, T::Hash[String, String]) }
      EventEnvelope = T.type_alias { T::Hash[String, EventValue] }

      sig do
        params(
          client: VerifiedDelivery::Transport,
          local_bot_ids: T::Array[String],
          peer_bot_ids: T::Array[String]
        ).void
      end
      def initialize(client, local_bot_ids: [], peer_bot_ids: [])
        @client = client
        @local = local_bot_ids
        @peers = peer_bot_ids
      end

      sig { params(envelope: EventEnvelope).returns(VerifiedDelivery) }
      def event(envelope)
        kind = event_string(envelope, "event")
        validate_event_kind!(kind)

        candidate = post_from(parsed_post(event_data(envelope).fetch("post")))
        broadcast = optional_broadcast_channel(envelope)
        raise ArgumentError, "Event channel mismatch" if broadcast && broadcast != candidate.channel_id

        delivery(post_id: candidate.id, channel_id: candidate.channel_id, event_kind: kind)
      end

      sig { override.params(post_id: String, channel_id: String, event_kind: String).returns(VerifiedDelivery) }
      def delivery(post_id:, channel_id:, event_kind:)
        identifier!(post_id)
        identifier!(channel_id)
        validate_event_kind!(event_kind)

        post = post_from(@client.get("/api/v4/posts/#{post_id}"))
        raise ArgumentError, "Post/channel mismatch" unless post.id == post_id && post.channel_id == channel_id

        sender = identifier!(post.user_id)
        post_root_id = post.root_id
        thread = identifier!(post_root_id.nil? || post_root_id.empty? ? post_id : post_root_id)
        root = thread == post_id ? post : post_from(@client.get("/api/v4/posts/#{thread}"))
        root_root_id = root.root_id
        raise ArgumentError,
              "Cross-channel or non-root thread" unless root.id == thread && root.channel_id == channel_id && (root_root_id.nil? || root_root_id.empty?)

        revision = revision(post)
        revision(root)
        raise ArgumentError, "Deleted thread root" unless root.delete_at.zero?
        raise ArgumentError, "Deleted post" if event_kind != "post_deleted" && !post.delete_at.zero?

        channel = channel_from(@client.get("/api/v4/channels/#{channel_id}"))
        raise ArgumentError, "Channel identity mismatch" unless channel.id == channel_id

        member = membership_from(@client.get("/api/v4/channels/#{channel_id}/members/#{sender}"))
        raise ArgumentError,
              "Revoked membership" unless member.channel_id == channel_id && member.user_id == sender

        user = user_from(@client.get("/api/v4/users/#{sender}"))
        raise ArgumentError, "Unverified sender" unless user.id == sender && user.delete_at.zero?

        # v11.11.1 omits false in authenticated User.IsBot JSON; never derive
        # this default from WS candidate fields or model-supplied context.
        raise ArgumentError, "Own bot loop" if @local.include?(sender)

        actor = Domains::Workflows::Entities::Actor.new(user_id: sender, channel_id: channel_id, member: true,
                                                        bot: user.bot || @peers.include?(sender))
        VerifiedDelivery.new(channel_id: channel_id, post_id: post_id, thread_id: thread, actor: actor,
                             event_kind: event_kind, post_revision: revision, body: post.message, root_post: post_id == thread)
      rescue KeyError, JSON::ParserError, TypeError => e
        raise ArgumentError, "Malformed server delivery (#{e.class})"
      end

      sig { params(post: VerifiedDelivery::Post).returns(Integer) }
      def revision(post)
        values = [post.create_at, post.update_at, post.delete_at]
        raise ArgumentError, "Invalid post revision" unless values.all? { |value| value >= 0 }

        values.max
      end

      sig { params(value: String).returns(String) }
      def identifier!(value)
        raise ArgumentError,
              "Invalid Mattermost identifier" unless value.match?(/\A[a-z0-9]{26}\z/)

        value
      end

      private

      sig { params(event_kind: String).void }
      def validate_event_kind!(event_kind)
        raise ArgumentError, "Unsupported event" unless KINDS.include?(event_kind)
      end

      sig { params(envelope: EventEnvelope, key: String).returns(String) }
      def event_string(envelope, key)
        value = envelope.fetch(key)
        raise ArgumentError, "Malformed event" unless value.is_a?(String)

        value
      end

      sig { params(envelope: EventEnvelope).returns(T::Hash[String, String]) }
      def event_data(envelope)
        value = envelope.fetch("data")
        raise ArgumentError, "Malformed event data" unless value.is_a?(Hash) && value.values.all? { |item| item.is_a?(String) }

        value
      end

      sig { params(envelope: EventEnvelope).returns(T.nilable(String)) }
      def optional_broadcast_channel(envelope)
        value = envelope["broadcast"]
        return nil if value.nil?

        raise ArgumentError, "Malformed event broadcast" unless value.is_a?(Hash) && value.values.all? { |item| item.is_a?(String) }

        value["channel_id"]
      end

      sig { params(serialized_post: String).returns(VerifiedDelivery::TransportResponse) }
      def parsed_post(serialized_post)
        parsed = JSON.parse(serialized_post)
        raise ArgumentError, "Malformed event post" unless parsed.is_a?(Hash)

        response = T.let({}, VerifiedDelivery::TransportResponse)
        parsed.each do |key, value|
          raise ArgumentError, "Malformed event post" unless key.is_a?(String) && transport_value?(value)

          response[key] = value
        end
        response
      end

      sig { params(value: Object).returns(T::Boolean) }
      def transport_value?(value)
        value.is_a?(String) || value.is_a?(Integer) || value == true || value == false || value.nil?
      end

      sig { params(response: VerifiedDelivery::TransportResponse).returns(VerifiedDelivery::Post) }
      def post_from(response)
        VerifiedDelivery::Post.new(id: identifier!(string_value(response, "id")),
                                   channel_id: identifier!(string_value(response, "channel_id")),
                                   user_id: identifier!(string_value(response, "user_id")),
                                   root_id: optional_string_value(response, "root_id"),
                                   message: string_value(response, "message"),
                                   create_at: non_negative_integer(response, "create_at"),
                                   update_at: non_negative_integer(response, "update_at"),
                                   delete_at: non_negative_integer(response, "delete_at"))
      end

      sig { params(response: VerifiedDelivery::TransportResponse).returns(VerifiedDelivery::Channel) }
      def channel_from(response)
        VerifiedDelivery::Channel.new(id: identifier!(string_value(response, "id")))
      end

      sig { params(response: VerifiedDelivery::TransportResponse).returns(VerifiedDelivery::Membership) }
      def membership_from(response)
        VerifiedDelivery::Membership.new(channel_id: identifier!(string_value(response, "channel_id")),
                                         user_id: identifier!(string_value(response, "user_id")))
      end

      sig { params(response: VerifiedDelivery::TransportResponse).returns(VerifiedDelivery::User) }
      def user_from(response)
        VerifiedDelivery::User.new(id: identifier!(string_value(response, "id")),
                                   delete_at: optional_non_negative_integer(response, "delete_at"),
                                   bot: optional_boolean(response, "is_bot"))
      end

      sig { params(response: VerifiedDelivery::TransportResponse, key: String).returns(String) }
      def string_value(response, key)
        value = response.fetch(key)
        raise ArgumentError, "Malformed server response" unless value.is_a?(String)

        value
      end

      sig { params(response: VerifiedDelivery::TransportResponse, key: String).returns(T.nilable(String)) }
      def optional_string_value(response, key)
        value = response[key]
        raise ArgumentError, "Malformed server response" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(response: VerifiedDelivery::TransportResponse, key: String).returns(Integer) }
      def non_negative_integer(response, key)
        value = response.fetch(key)
        raise ArgumentError, "Invalid post revision" unless value.is_a?(Integer) && value >= 0

        value
      end

      sig { params(response: VerifiedDelivery::TransportResponse, key: String).returns(Integer) }
      def optional_non_negative_integer(response, key)
        return 0 unless response.key?(key)

        non_negative_integer(response, key)
      end

      sig { params(response: VerifiedDelivery::TransportResponse, key: String).returns(T::Boolean) }
      def optional_boolean(response, key)
        return false unless response.key?(key)

        value = response.fetch(key)
        raise ArgumentError, "Unverified bot status" unless value == true || value == false

        value
      end
    end
  end
end
