# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    module Dto
      # Expected failure codes of the review use cases.
      class ErrorCode < T::Enum
        enums do
          InvalidCallback = new("invalid_callback")
          InvalidArtifact = new("invalid_artifact")
          InvalidVerdict = new("invalid_verdict")
        end
      end
    end
  end
end
