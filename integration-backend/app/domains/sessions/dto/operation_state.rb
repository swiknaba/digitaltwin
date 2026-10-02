# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # Values of the session_operation_state constraint.
      class OperationState < T::Enum
        extend T::Sig

        enums do
          Queued = new("queued")
          Sending = new("sending")
          Uncertain = new("uncertain")
          Complete = new("complete")
          Blocked = new("blocked")
        end

        # A start in one of these states is not settled, so no new session may replace it.
        sig { returns(T::Boolean) }
        def pending? = [Queued, Sending, Uncertain].include?(self)

        # The runtime effect may have happened; only reconciliation settles it.
        sig { returns(T::Boolean) }
        def unsettled? = [Sending, Uncertain].include?(self)
      end
    end
  end
end
