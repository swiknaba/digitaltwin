# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    module Dto
      # What to do when the repository is not yet checked out.
      class EnrollChoice < T::Enum
        enums do
          Clone = new("clone")
          CreatePrivate = new("create_private")
          Stop = new("stop")
        end
      end
    end
  end
end
