# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # Last verified agent status of a session. The values mirror Herdr's
      # AgentStatus; `unknown` is also the column default before a start.
      class SessionState < T::Enum
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
