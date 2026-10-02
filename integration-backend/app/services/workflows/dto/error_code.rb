# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    module Dto
      # Expected failure codes of the workflow use cases. Details keep today's
      # ArgumentError messages.
      class ErrorCode < T::Enum
        enums do
          UnknownProject = new("unknown_project")
          InvalidTitle = new("invalid_title")
          UnverifiedExistingThread = new("unverified_existing_thread")
          RolesMissing = new("roles_missing")
          DiversityRequired = new("diversity_required")
          MissingRequest = new("missing_request")
          UnverifiedThreadBot = new("unverified_thread_bot")
          WorktreeChanged = new("worktree_changed")
          InvalidThread = new("invalid_thread")
          RecoveryNotAuthorized = new("recovery_not_authorized")
          RecoveryThreadChanged = new("recovery_thread_changed")
          NotReconcilable = new("not_reconcilable")
          LeaseLive = new("lease_live")
          UnprovedThread = new("unproved_thread")
          UnsupportedAction = new("unsupported_action")
          MissingWorkflow = new("missing_workflow")
          MissingSource = new("missing_source")
          SessionMissing = new("session_missing")
          SessionUncertain = new("session_uncertain")
          PausedRevisionChanged = new("paused_revision_changed")
          ApprovalPhaseMismatch = new("approval_phase_mismatch")
          ApprovalMissing = new("approval_missing")
          ReviewMissing = new("review_missing")
          PriorApprovalMissing = new("prior_approval_missing")
          InvalidArtifact = new("invalid_artifact")
          PhaseChanged = new("phase_changed")
          SourceMismatch = new("source_mismatch")
          StartRequired = new("start_required")
          ProjectMappingRequired = new("project_mapping_required")
          MalformedJob = new("malformed_job")
        end
      end
    end
  end
end
