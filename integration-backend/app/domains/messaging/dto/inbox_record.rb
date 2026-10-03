# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # A persisted verified delivery.
      class InboxRecord < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :channel_id, String
        const :thread_id, String
        const :post_id, String
        const :user_id, String
        const :event_kind, EventKind
        const :post_revision, Integer
        const :verified_delivery, VerifiedDelivery
        const :created_at, Time
      end
    end
  end
end
