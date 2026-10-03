# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # A human confirmation request for a parameter-bound action.
      class ConfirmationView < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :requesting_user_id, String
        const :channel_id, String
        const :action, String
        const :parameter_digest, String
        const :expires_at, Time
        const :consumed_at, T.nilable(Time)
        const :confirming_user_id, T.nilable(String)
        const :confirming_post_id, T.nilable(String)
      end
    end
  end
end
