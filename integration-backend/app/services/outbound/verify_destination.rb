# typed: strict
# frozen_string_literal: true

module Services
  module Outbound
    # Proves bot identity, channel membership, and the thread root before an
    # outbox message is posted or reconciled. Raises ArgumentError otherwise.
    class VerifyDestination
      extend T::Sig

      Api = Adapters::Mattermost::Api

      sig { params(api: Api, item: Domains::Messaging::Dto::OutboxItem, bot: String).void }
      def call(api:, item:, bot:)
        [item.channel_id, bot, item.thread_id].compact.each { |identifier| identifier!(identifier) }
        me = api.me
        raise ArgumentError, "Wrong bot identity" unless me.id == bot && me.bot

        channel = api.channel(item.channel_id)
        member = api.member(channel_id: item.channel_id, user_id: bot)
        valid_membership = [channel.id == item.channel_id, member&.channel_id == item.channel_id, member&.user_id == bot].all?
        raise ArgumentError, "Bot/channel membership mismatch" unless valid_membership

        thread_id = item.thread_id
        return unless thread_id

        root = api.post(thread_id)
        valid_root = [root.id == thread_id, root.channel_id == item.channel_id, root.root_id.to_s.empty?, root.delete_at.zero?].all?
        raise ArgumentError, "Invalid source thread" unless valid_root
      end

      sig { params(value: String).returns(String) }
      private def identifier!(value)
        raise ArgumentError, "Invalid Mattermost destination ID" unless value.match?(Api::IDENTIFIER)

        value
      end
    end
  end
end
