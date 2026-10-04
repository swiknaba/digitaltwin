# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # Values of the session_role constraint. Only operator bootstrap creates a commander.
      class SessionRole < T::Enum
        enums do
          Writer = new("writer")
          Reviewer = new("reviewer")
          Commander = new("commander")
        end
      end
    end
  end
end
