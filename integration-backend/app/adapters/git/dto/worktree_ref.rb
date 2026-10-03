# typed: strict
# frozen_string_literal: true

module Adapters
  module Git
    module Dto
      # A workflow worktree and the branch it must have checked out.
      class WorktreeRef < T::Struct
        include Kirei::Domain::ValueObject

        const :worktree_path, String
        const :branch, String
      end
    end
  end
end
