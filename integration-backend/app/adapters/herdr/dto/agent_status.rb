# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    module Dto
      # Values of AgentStatus in agent-runtime/contracts/herdr-v0.9.3.schema.json.
      class AgentStatus < T::Enum
        extend T::Sig

        enums do
          Idle = new("idle")
          Working = new("working")
          Blocked = new("blocked")
          Done = new("done")
          Unknown = new("unknown")
        end

        # The agent finished its turn; a new prompt or a stop is safe.
        sig { returns(T::Boolean) }
        def settled? = [Idle, Done].include?(self)

        # The agent runs a known conversation turn or waits; it is not blocked or unknown.
        sig { returns(T::Boolean) }
        def live? = [Idle, Working, Done].include?(self)
      end
    end
  end
end
