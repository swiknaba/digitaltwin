# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # Values of the session_operation_kind constraint.
      class OperationKind < T::Enum
        enums do
          Start = new("start")
          Stop = new("stop")
        end
      end
    end
  end
end
