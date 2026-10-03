# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    # Refetches a post through authenticated chat REST and proves its sender,
    # thread, channel, and membership. Implementations raise ArgumentError for
    # a permanent rejection and a transport error for a transient failure.
    module DeliveryVerifier
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(post_id: String, channel_id: String, event_kind: Dto::EventKind).returns(Dto::VerifiedDelivery) }
      def delivery(post_id:, channel_id:, event_kind:); end
    end
  end
end
