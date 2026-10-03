# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # One `workflows` row with every column typed.
      class WorkflowView < T::Struct
        extend T::Sig
        include Kirei::Domain::ValueObject

        const :id, String
        const :project_id, String
        const :channel_id, String
        const :thread_id, String
        const :branch, String
        const :worktree_path, String
        const :phase, Phase
        const :saved_phase, T.nilable(Phase)
        const :version, Integer
        const :artifacts, ArtifactSet
        const :blocker, T.nilable(String)
        const :archived_at, T.nilable(Time)
        const :created_at, Time
        const :paused_commit, T.nilable(String)
        const :source_inbox_id, T.nilable(String)
        const :role_configurations, RoleAssignments

        # The phase that governs work: a paused workflow keeps its saved phase.
        sig { returns(T.nilable(Phase)) }
        def effective_phase = phase == Phase::Paused ? saved_phase : phase
      end
    end
  end
end
