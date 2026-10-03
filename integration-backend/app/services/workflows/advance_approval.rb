# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Moves a workflow past a human approval gate. It requires the exact human
    # approval, the latest approving review of the same commit, unchanged git
    # evidence, and the earlier gates' approvals.
    class AdvanceApproval
      extend T::Sig

      Code = Dto::ErrorCode
      Gate = Domains::Workflows::Dto::Gate
      Outcome = T.type_alias { Kirei::Services::Result[Domains::Workflows::Dto::WorkflowView] }

      sig do
        params(evidence: Adapters::Git::Evidence, rounds: Domains::Reviews::Rounds, queue_release: Reviews::QueueRelease,
               catalog: Domains::Workflows::Catalog, transitions: Domains::Workflows::Transitions, approvals: Domains::Workflows::Approvals,
               phase_prompts: Domains::Workflows::PhasePrompts).void
      end
      def initialize(evidence:, rounds: Domains::Reviews::Rounds.new, queue_release: Reviews::QueueRelease.new, catalog: Domains::Workflows::Catalog.new,
                     transitions: Domains::Workflows::Transitions.new, approvals: Domains::Workflows::Approvals.new, phase_prompts: Domains::Workflows::PhasePrompts.new)
        @evidence = evidence
        @rounds = rounds
        @queue_release = queue_release
        @catalog = catalog
        @transitions = transitions
        @approvals = approvals
        @prior_approvals = T.let(VerifyPriorApprovals.new(evidence: evidence, approvals: approvals), VerifyPriorApprovals)
        @phase_prompts = phase_prompts
      end

      sig { params(workflow_id: String, gate: Gate).returns(Outcome) }
      def call(workflow_id:, gate:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          Platform::Lock.new.call(key: workflow_id) { advance(workflow_id, gate) }
        end
      end

      sig { params(workflow_id: String, gate: Gate).returns(Outcome) }
      private def advance(workflow_id, gate)
        workflow = @catalog.find(id: workflow_id)
        return failure(Code::MissingWorkflow, "Missing workflow") unless workflow
        return failure(Code::ApprovalPhaseMismatch, "Approval phase mismatch") unless gate.human_approval_phase == workflow.phase

        ref = workflow.artifacts.fetch(gate)
        return failure(Code::ApprovalMissing, "Exact human approval missing") unless ref && @approvals.find(workflow_id: workflow_id, gate: gate, commit: ref.commit)

        review = @rounds.latest(workflow_id: workflow_id, gate: gate)
        approving = review&.verdict == Domains::Reviews::Dto::Verdict::Approve && review&.target_commit == ref.commit
        return failure(Code::ReviewMissing, "Approving review missing") unless review && approving

        worktree = Adapters::Git::Dto::WorktreeRef.new(worktree_path: workflow.worktree_path, branch: workflow.branch)
        @evidence.approval(worktree: worktree, binding: ref, target_commit: review.target_commit, review_commit: review.review_commit, review_path: review.review_path)
        prior = @prior_approvals.call(workflow: workflow, gates: gate.approved_gates)
        return prior if prior.failed?

        version = workflow.version + 1
        Platform::Transaction.new.call do
          advanced = @transitions.advance_approval(workflow_id: workflow_id, gate: gate, expected_version: workflow.version)
          next advanced if advanced.failed?

          @phase_prompts.enqueue(workflow_id: workflow_id, version: version)
          @queue_release.call(workflow_id: workflow_id, version: version)
          advanced
        end
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
