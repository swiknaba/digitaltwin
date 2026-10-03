# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # Values of the session_role constraint. Only operator bootstrap creates a controller.
      class SessionRole < T::Enum
        enums do
          Writer = new("writer")
          Reviewer = new("reviewer")
          Controller = new("controller")
        end
      end
    end
  end
end
