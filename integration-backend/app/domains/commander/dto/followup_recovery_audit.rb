# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # Audit details of a human follow-up delivery reconciliation.
      class FollowupRecoveryAudit < T::Struct
        include Kirei::Domain::ValueObject

        const :inbox_id, String
        const :followup_id, String
        const :workflow_id, String
        const :session_id, String
        const :generation, Integer
        const :user_id, String
        const :outcome, String
      end
    end
  end
end
