# typed: strict
# frozen_string_literal: true

module Services
  module Master
    # Records a human spec or plan approval once, from the exact Master-chat
    # approve command or a verified `@worker approve` in the workflow thread.
    # Only the latest approving review of the current revision binds. Returns
    # the approval id.
    class RecordApproval
      extend T::Sig

      Code = Dto::ErrorCode
      Gate = Domains::Workflows::Dto::Gate
      Workflow = Domains::Workflows::Dto::WorkflowView
      CurrentCommitSource = T.type_alias { T.proc.params(worktree: Adapters::Git::Dto::WorktreeRef).returns(String) }
      Outcome = T.type_alias { Kirei::Services::Result[String] }

      sig do
        params(resolver: Domains::Messaging::DeliveryVerifier, membership: Domains::Messaging::MembershipCheck, current_commit: CurrentCommitSource,
               evidence: T.nilable(Adapters::Git::Evidence), handle: String, worker_handle: String, inbox: Domains::Messaging::Inbox,
               catalog: Domains::Workflows::Catalog, rounds: Domains::Reviews::Rounds, approvals: Domains::Workflows::Approvals,
               lock: Platform::Lock, transaction: Platform::Transaction).void
      end
      def initialize(resolver:, membership:, current_commit:, evidence: nil, handle: ENV.fetch("AGENT_HANDLE", "agent"),
                     worker_handle: ENV.fetch("WORKER_HANDLE", "worker"), inbox: Domains::Messaging::Inbox.new, catalog: Domains::Workflows::Catalog.new,
                     rounds: Domains::Reviews::Rounds.new, approvals: Domains::Workflows::Approvals.new, lock: Platform::Lock.new,
                     transaction: Platform::Transaction.new)
        @resolver = resolver
        @membership = membership
        @current_commit = current_commit
        @evidence = evidence
        @handle = handle
        @worker_handle = worker_handle
        @inbox = inbox
        @catalog = catalog
        @rounds = rounds
        @approvals = approvals
        @lock = lock
        @transaction = transaction
      end

      sig { params(inbox_id: String, workflow_id: String, gate: Gate, commit: String).returns(Outcome) }
      def call(inbox_id:, workflow_id:, gate:, commit:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          next failure(Code::ApprovalRejected, "Exact approval required") unless [Gate::Spec, Gate::Plan].include?(gate) && commit.match?(/\A[0-9a-f]{40}\z/)

          source = @inbox.find(id: inbox_id)
          next failure(Code::MissingSource, "Missing source") unless source

          d = @resolver.delivery(post_id: source.post_id, channel_id: source.channel_id, event_kind: Domains::Messaging::Dto::EventKind::Posted)
          unless d.actor.member && !d.actor.bot && d.actor.user_id == source.user_id && d.post_revision == source.post_revision
            next failure(Code::SourceChanged, "Human source changed")
          end

          w = @catalog.find(id: workflow_id)
          next failure(Code::MissingWorkflow, "Missing workflow") unless w

          contextual = d.channel_id == w.channel_id && d.thread_id == w.thread_id && d.body == "@#{@worker_handle} approve"
          exact = d.body == "@#{@handle} approve #{workflow_id} #{gate.serialize} #{commit}"
          next failure(Code::ApprovalRejected, "Approval requires exact or verified thread binding") unless exact || contextual
          next failure(Code::MembershipRequired, "Destination membership required") unless @membership.member?(channel_id: w.channel_id, user_id: d.actor.user_id)

          @lock.call(key: workflow_id) { record(w, gate, commit, d) }
        rescue Platform::Lock::Busy => error
          failure(Code::Busy, error.message)
        end
      end

      sig { params(w: Workflow, gate: Gate, commit: String, d: Domains::Messaging::Dto::VerifiedDelivery).returns(Outcome) }
      private def record(w, gate, commit, d)
        current = @current_commit.call(worktree(w))
        @transaction.call do
          locked = @catalog.find_for_update(id: w.id)
          next failure(Code::MissingWorkflow, "Missing workflow") unless locked

          review = @rounds.latest(workflow_id: w.id, gate: gate)
          review_commit = review&.review_commit
          approved = review && review.verdict == Domains::Reviews::Dto::Verdict::Approve && review.target_commit == commit && current == (review_commit || commit)
          unless !locked.archived_at && locked.phase.serialize == "#{gate.serialize}_human_approval" && review && approved
            next failure(Code::ApprovalStale, "Approval binding is stale")
          end

          @evidence&.approval(worktree: worktree(locked), binding: locked.artifacts.fetch(gate), target_commit: commit,
                              review_commit: review_commit, review_path: review.review_path)
          recorded = @approvals.record(workflow_id: w.id, gate: gate, target_commit: commit, user_id: d.actor.user_id, channel_id: d.channel_id, post_id: d.post_id)
          next Kirei::Services::Result.new(errors: recorded.errors) if recorded.failed?

          Kirei::Services::Result.new(result: recorded.result.id)
        end
      end

      sig { params(workflow: Workflow).returns(Adapters::Git::Dto::WorktreeRef) }
      private def worktree(workflow)
        Adapters::Git::Dto::WorktreeRef.new(worktree_path: workflow.worktree_path, branch: workflow.branch)
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
