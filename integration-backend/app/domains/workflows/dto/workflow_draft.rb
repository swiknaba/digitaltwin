# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # The values a start request binds to a new workflow. Requests#bind
      # derives the id, branch and worktree path.
      class WorkflowDraft < T::Struct
        include Kirei::Domain::ValueObject

        const :project_id, String
        const :channel_id, String
        const :thread_id, String
        const :worktree_root, String
        const :source_inbox_id, Integer
        const :role_configurations, RoleAssignments
      end
    end
  end
end
