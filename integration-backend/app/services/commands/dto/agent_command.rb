# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # `@<agent> <action>`. The start re-verification requires one space.
      class AgentCommand < T::Struct
        include Kirei::Domain::ValueObject

        const :action, AgentAction
        const :single_space_separator, T::Boolean
      end
    end
  end
end
