# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # Expected failure codes of the commander domain.
      class ErrorCode < T::Enum
        enums do
          CapabilityRejected = new("capability_rejected")
        end
      end
    end
  end
end
