# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # Audit details of a human-verified session operation reconciliation.
      class SessionRecoveryAudit < T::Struct
        include Kirei::Domain::ValueObject

        const :inbox_id, Integer
        const :operation_id, String
        const :session_id, String
        const :generation, Integer
        const :pane_id, String
      end
    end
  end
end
