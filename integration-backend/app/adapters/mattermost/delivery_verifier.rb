# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    # Refetches a candidate post, its thread root, channel, membership, and
    # sender through authenticated REST before it becomes a verified delivery.
    # Until Task 4 it returns the Mattermost domain's VerifiedDelivery.
    class DeliveryVerifier
      extend T::Sig
      include Domains::Commander::Source::DeliveryResolver

      KINDS = T.let(["posted", "post_edited", "post_deleted"].freeze, T::Array[String])
      EventValue = T.type_alias { T.any(String, Integer, T::Hash[String, String]) }
      EventEnvelope = T.type_alias { T::Hash[String, EventValue] }

      sig { params(api: Api, local_bot_ids: T::Array[String], peer_bot_ids: T::Array[String]).void }
      def initialize(api:, local_bot_ids: [], peer_bot_ids: [])
        @api = api
        @local = local_bot_ids
        @peers = peer_bot_ids
      end

      sig { params(envelope: EventEnvelope).returns(Domains::Mattermost::VerifiedDelivery) }
      def event(envelope)
        kind = event_string(envelope, "event")
        validate_event_kind!(kind)

        candidate = @api.event_post(serialized: event_data(envelope).fetch("post"))
        broadcast = optional_broadcast_channel(envelope)
        raise ArgumentError, "Event channel mismatch" if broadcast && broadcast != candidate.channel_id

        delivery(post_id: identifier!(candidate.id), channel_id: identifier!(candidate.channel_id), event_kind: kind)
      end

      sig { override.params(post_id: String, channel_id: String, event_kind: String).returns(Domains::Mattermost::VerifiedDelivery) }
      def delivery(post_id:, channel_id:, event_kind:)
        identifier!(post_id)
        identifier!(channel_id)
        validate_event_kind!(event_kind)

        post = @api.post(post_id)
        raise ArgumentError, "Post/channel mismatch" unless post.id == post_id && post.channel_id == channel_id

        sender = identifier!(post.user_id)
        post_root_id = post.root_id
        thread = identifier!(post_root_id.nil? || post_root_id.empty? ? post_id : post_root_id)
        root = thread == post_id ? post : @api.post(thread)
        root_root_id = root.root_id
        raise ArgumentError,
              "Cross-channel or non-root thread" unless root.id == thread && root.channel_id == channel_id && (root_root_id.nil? || root_root_id.empty?)

        revision = revision(post)
        revision(root)
        raise ArgumentError, "Deleted thread root" unless root.delete_at.zero?
        raise ArgumentError, "Deleted post" if event_kind != "post_deleted" && !post.delete_at.zero?

        channel = @api.channel(channel_id)
        raise ArgumentError, "Channel identity mismatch" unless identifier!(channel.id) == channel_id

        # A failed membership fetch raises RequestFailed with its HTTP status
        # instead of becoming a permanent rejection.
        member = @api.member!(channel_id: channel_id, user_id: sender)
        raise ArgumentError, "Revoked membership" unless member.channel_id == channel_id && member.user_id == sender

        user = @api.user(sender)
        raise ArgumentError, "Unverified sender" unless user.id == sender && user.delete_at.zero?

        # v11.11.1 omits false in authenticated User.IsBot JSON; never derive
        # this default from WS candidate fields or model-supplied context.
        raise ArgumentError, "Own bot loop" if @local.include?(sender)

        actor = Domains::Workflows::Entities::Actor.new(user_id: sender, channel_id: channel_id, member: true,
                                                        bot: user.bot || @peers.include?(sender))
        Domains::Mattermost::VerifiedDelivery.new(channel_id: channel_id, post_id: post_id, thread_id: thread, actor: actor,
                                                  event_kind: event_kind, post_revision: revision, body: post.message, root_post: post_id == thread)
      end

      sig { params(post: Dto::Post).returns(Integer) }
      def revision(post)
        [post.create_at, post.update_at, post.delete_at].max
      end

      sig { params(value: String).returns(String) }
      def identifier!(value)
        raise ArgumentError,
              "Invalid Mattermost identifier" unless value.match?(Api::IDENTIFIER)

        value
      end

      private

      sig { params(event_kind: String).void }
      def validate_event_kind!(event_kind)
        raise ArgumentError, "Unsupported event" unless KINDS.include?(event_kind)
      end

      sig { params(envelope: EventEnvelope, key: String).returns(String) }
      def event_string(envelope, key)
        value = envelope.fetch(key) { raise ArgumentError, "Malformed event" }
        raise ArgumentError, "Malformed event" unless value.is_a?(String)

        value
      end

      sig { params(envelope: EventEnvelope).returns(T::Hash[String, String]) }
      def event_data(envelope)
        value = envelope.fetch("data") { raise ArgumentError, "Malformed event data" }
        raise ArgumentError, "Malformed event data" unless value.is_a?(Hash) && value.values.all? { |item| item.is_a?(String) } && value.key?("post")

        value
      end

      sig { params(envelope: EventEnvelope).returns(T.nilable(String)) }
      def optional_broadcast_channel(envelope)
        value = envelope["broadcast"]
        return nil if value.nil?

        raise ArgumentError, "Malformed event broadcast" unless value.is_a?(Hash) && value.values.all? { |item| item.is_a?(String) }

        value["channel_id"]
      end
    end
  end
end
