# typed: strict

module Domains
  module Mattermost
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
