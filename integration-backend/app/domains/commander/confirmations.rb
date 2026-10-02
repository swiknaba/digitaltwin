# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    # Read access to human confirmations of parameter-bound actions. No
    # production path writes confirmations yet.
    class Confirmations
      extend T::Sig

      sig { params(id: String).returns(T.nilable(Dto::ConfirmationView)) }
      def find(id:)
        entity = Entities::Confirmation.find_by(id: id)
        entity && Dto::ConfirmationView.new(
          id: entity.id, requesting_user_id: entity.requesting_user_id, channel_id: entity.channel_id, action: entity.action,
          parameter_digest: entity.parameter_digest, expires_at: entity.expires_at, consumed_at: entity.consumed_at,
          confirming_user_id: entity.confirming_user_id, confirming_post_id: entity.confirming_post_id
        )
      end
    end
  end
end
