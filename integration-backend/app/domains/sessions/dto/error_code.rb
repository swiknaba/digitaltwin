# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # Expected failure codes of the sessions domain.
      class ErrorCode < T::Enum
        enums do
          InvalidSession = new("invalid_session")
          StaleGeneration = new("stale_generation")
          SessionActive = new("session_active")
          IncompleteConfiguration = new("incomplete_configuration")
          KeyReused = new("key_reused")
        end
      end
    end
  end
end
