# typed: strict
# frozen_string_literal: true

module Services
  module Outbound
    module Dto
      # Expected failure codes of outbound delivery use cases.
      class ErrorCode < T::Enum
        enums do
          NotUncertain = new("not_uncertain")
          MalformedHistory = new("malformed_history")
        end
      end
    end
  end
end
