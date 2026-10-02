# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    # Identity of a post that Adapters::Mattermost::DeliveryVerifier proved
    # through authenticated REST.
    class VerifiedDelivery < T::Struct
      const :channel_id, String
      const :post_id, String
      const :thread_id, String
      const :actor, Domains::Workflows::Entities::Actor
      const :event_kind, String
      const :post_revision, Integer
      const :body, String
      const :root_post, T::Boolean
    end
  end
end
