# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    module Dto
      # Expected failure codes of session use cases.
      class ErrorCode < T::Enum
        enums do
          InvalidCallback = new("invalid_callback")
          InvalidSession = new("invalid_session")
          InactiveWorkflow = new("inactive_workflow")
          InactiveRole = new("inactive_role")
          StaleGeneration = new("stale_generation")
          CallbackKeyReused = new("callback_key_reused")
          MalformedRecord = new("malformed_record")
        end
      end
    end
  end
end
