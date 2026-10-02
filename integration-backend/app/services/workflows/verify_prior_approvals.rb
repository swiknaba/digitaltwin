# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Proves that each earlier gate still has its exact human approval and that
    # the approved artifact is unchanged at the current revision.
    class VerifyPriorApprovals
      extend T::Sig

      Code = Dto::ErrorCode
      Workflow = Domains::Workflows::Dto::WorkflowView
      Outcome = T.type_alias { Kirei::Services::Result[Workflow] }

      sig { params(evidence: Adapters::Git::Evidence, approvals: Domains::Workflows::Approvals).void }
      def initialize(evidence:, approvals: Domains::Workflows::Approvals.new)
        @evidence = evidence
        @approvals = approvals
      end

      sig { params(workflow: Workflow, gates: T::Array[Domains::Workflows::Dto::Gate]).returns(Outcome) }
      def call(workflow:, gates:)
        worktree = Adapters::Git::Dto::WorktreeRef.new(worktree_path: workflow.worktree_path, branch: workflow.branch)
        gates.each do |gate|
          ref = workflow.artifacts.fetch(gate)
          return failure(Code::InvalidArtifact, "Invalid workflow artifact") unless ref
          return failure(Code::PriorApprovalMissing, "Required exact artifact approval missing") unless @approvals.find(workflow_id: workflow.id, gate: gate, commit: ref.commit)

          @evidence.approved_artifact(worktree: worktree, binding: ref, target_commit: ref.commit)
        end
        Kirei::Services::Result.new(result: workflow)
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
