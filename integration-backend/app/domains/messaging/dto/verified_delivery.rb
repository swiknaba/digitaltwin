# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # A post that the delivery verifier proved through authenticated REST. Its serialized form is the inbox.verified_delivery JSON.
      class VerifiedDelivery < T::Struct
        include Kirei::Domain::ValueObject

        const :channel_id, String
        const :post_id, String
        const :thread_id, String
        const :actor, VerifiedActor
        const :event_kind, EventKind
        const :post_revision, Integer
        const :body, String
        const :root_post, T::Boolean
      end
    end
  end
end
