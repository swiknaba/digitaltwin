# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    module Dto
      # Conversation identity (Herdr AgentSessionInfo).
      class AgentSession < T::Struct
        include Kirei::Domain::ValueObject

        const :source, String
        const :agent, String
        const :kind, String
        const :value, String
      end
    end
  end
end
