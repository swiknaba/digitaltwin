# typed: strict
# frozen_string_literal: true

module Services
  module Outbound
    # Proves that a server post is the delivery of an outbox message.
    class VerifyPostedResult
      extend T::Sig

      sig { params(post: Adapters::Mattermost::Dto::Post, item: Domains::Messaging::Dto::OutboxItem, bot: String).void }
      def call(post:, item:, bot:)
        verified = [post.id.match?(Adapters::Mattermost::Api::IDENTIFIER), post.channel_id == item.channel_id, post.root_id.to_s == item.thread_id.to_s,
                    post.user_id == bot, post.message == item.body].all?
        raise "Unverified Mattermost delivery result" unless verified
      end
    end
  end
end
