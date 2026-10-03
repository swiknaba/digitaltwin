# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    # Handles review.prompt: sends the round's reviewer prompt once. The
    # dispatch state moves queued -> sending -> delivered. A failure after the
    # lease's effect began leaves it uncertain; it is never resent, and a
    # verified review result settles it (ReviewFinished).
    class DispatchReview
      extend T::Sig
      include Platform::Jobs::Handler

      Decision = Platform::Jobs::Dto::Decision
      DispatchState = Domains::Reviews::Dto::DispatchState
      Review = Domains::Reviews::Dto::ReviewView
      Session = Domains::Sessions::Dto::SessionView
      Workflow = Domains::Workflows::Dto::WorkflowView
      MALFORMED = Domains::Reviews::Rounds::MALFORMED

      sig do
        params(herdr: Adapters::Herdr::Client, evidence: Adapters::Git::Evidence, policy: Domains::Workflows::Policy, rounds: Domains::Reviews::Rounds,
               registry: Domains::Sessions::Registry, catalog: Domains::Workflows::Catalog, lock: Platform::Lock).void
      end
      def initialize(herdr:, evidence:, policy: Domains::Workflows::Policy.new, rounds: Domains::Reviews::Rounds.new, registry: Domains::Sessions::Registry.new,
                     catalog: Domains::Workflows::Catalog.new, lock: Platform::Lock.new)
        @herdr = herdr
        @verify_settled = T.let(VerifySettled.new(herdr: herdr), VerifySettled)
        @evidence = evidence
        @policy = policy
        @rounds = rounds
        @registry = registry
        @catalog = catalog
        @lock = lock
      end

      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          review = @rounds.find(id: Domains::Reviews::Dto::ReviewPromptJob.from_hash(job.payload, true).review_id) or raise ArgumentError, MALFORMED
          @lock.call(key: review.workflow_id) { dispatch(review, job.lease) }
        end
      end

      sig { params(review: Review, lease: Platform::Jobs::Lease).returns(Decision) }
      private def dispatch(review, lease)
        return Decision.complete if review.dispatch_state == DispatchState::Delivered
        raise ArgumentError, "Uncertain review prompt" unless review.dispatch_state == DispatchState::Queued
        return Decision.block("Live review dispatch evidence required") unless @policy.dispatch_allowed?

        workflow = @catalog.find(id: review.workflow_id) or raise ArgumentError, MALFORMED
        return Decision.defer("Paused review") if workflow.phase == Domains::Workflows::Dto::Phase::Paused
        raise ArgumentError, "Review phase changed" unless workflow.phase.serialize == "#{review.gate.serialize}_review"

        worktree = Adapters::Git::Dto::WorktreeRef.new(worktree_path: workflow.worktree_path, branch: workflow.branch)
        @evidence.artifact(worktree: worktree, commit: review.target_commit, path: artifact_path(workflow, review))
        reviewer = @registry.active(workflow_id: workflow.id, role: Domains::Sessions::Dto::SessionRole::Reviewer).first
        raise ArgumentError, MALFORMED unless reviewer
        raise ArgumentError, "Reviewer configuration changed" unless reviewer.configuration.serialize == review.reviewer_configuration.serialize

        live = @herdr.pane(reviewer.pane_id)
        return Decision.defer("Reviewer busy") if live.agent_status == Adapters::Herdr::Dto::AgentStatus::Working && live.agent_session&.serialize == runtime_identity(reviewer)

        @verify_settled.call(session: reviewer)
        send_prompt(review, reviewer, lease)
        Decision.complete
      end

      sig { params(review: Review, reviewer: Session, lease: Platform::Jobs::Lease).void }
      private def send_prompt(review, reviewer, lease)
        @rounds.mark_dispatch(id: review.id, state: DispatchState::Sending)
        begin
          raise IOError, "Dispatch lease lost" unless lease.begin_effect

          prompt = "Review #{review.gate.serialize} target #{review.target_commit}, base #{review.base_commit}. " \
                   "Change only #{review.review_path}; append Target, Provider, Model, Family, Verdict and Reviewed-at (UTC ISO8601) fields. " \
                   "Report the exact review commit via review-ready. Do not change the artifact or start sessions."
          @herdr.prompt(pane_id: reviewer.pane_id, text: prompt)
          @rounds.mark_dispatch(id: review.id, state: DispatchState::Delivered)
        rescue StandardError
          @rounds.mark_dispatch(id: review.id, state: DispatchState::Uncertain)
          raise
        end
      end

      # Review sessions are always started, so a missing identity is a malformed record.
      sig { params(session: Session).returns(T::Hash[String, String]) }
      private def runtime_identity(session)
        identity = session.runtime_identity
        raise ArgumentError, MALFORMED unless identity

        identity.serialize
      end

      sig { params(workflow: Workflow, review: Review).returns(T.nilable(String)) }
      private def artifact_path(workflow, review)
        ref = workflow.artifacts.fetch(review.gate) or raise ArgumentError, "Malformed workflow record"
        ref.path
      end
    end
  end
end
