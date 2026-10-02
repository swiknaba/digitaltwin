# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    module Dto
      # Agent state of one pane (Herdr AgentInfo). Optional schema fields stay nilable.
      class Pane < T::Struct
        include Kirei::Domain::ValueObject

        const :pane_id, String
        const :name, T.nilable(String)
        const :cwd, T.nilable(String)
        const :agent, T.nilable(String)
        const :agent_status, AgentStatus
        const :agent_session, T.nilable(AgentSession)
        const :interactive_ready, T.nilable(T::Boolean)
        const :launch_pending, T.nilable(T::Boolean)
      end
    end
  end
end
