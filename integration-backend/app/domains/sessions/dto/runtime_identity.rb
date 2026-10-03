# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # The proven conversation identity of a started session. Its JSON shape
      # equals Herdr's AgentSessionInfo, so stored and live values compare by
      # `serialize`.
      class RuntimeIdentity < T::Struct
        include Kirei::Domain::ValueObject

        const :source, String
        const :agent, String
        const :kind, String
        const :value, String
      end
    end
  end
end
