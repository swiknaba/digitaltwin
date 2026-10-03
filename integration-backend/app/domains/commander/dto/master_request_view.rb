# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # One verified human request bound to the Controller session.
      class MasterRequestView < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :inbox_id, String
        const :session_id, String
        const :credential_digest, String
        const :expires_at, Time
        const :state, MasterRequestState
        const :reason, T.nilable(String)
      end
    end
  end
end
