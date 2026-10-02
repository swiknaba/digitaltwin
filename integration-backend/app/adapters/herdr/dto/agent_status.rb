# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    module Dto
      # Values of AgentStatus in agent-runtime/contracts/herdr-v0.9.3.schema.json.
      class AgentStatus < T::Enum
        enums do
          Idle = new("idle")
          Working = new("working")
          Blocked = new("blocked")
          Done = new("done")
          Unknown = new("unknown")
        end
      end
    end
  end
end
