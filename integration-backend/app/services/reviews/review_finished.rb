# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    # A Reviewer reports the exact review commit and verdict of the open round.
    # Under the workflow lock this verifies the dispatched prompt, the settled
    # Reviewer and the review evidence. One transaction then records the
    # verdict, enters the next phase, queues the release, the Writer prompt
    # and the chat notice. A replay of a recorded result returns its review id.
    class ReviewFinished
      extend T::Sig

      Gate = Domains::Workflows::Dto::Gate
      Phase = Domains::Workflows::Dto::Phase
      Role = Domains::Sessions::Dto::SessionRole
      Session = Domains::Sessions::Dto::SessionView
      Workflow = Domains::Workflows::Dto::WorkflowView
      Review = Domains::Reviews::Dto::ReviewView
      Verdict = Domains::Reviews::Dto::Verdict
      DispatchState = Domains::Reviews::Dto::DispatchState
      Rounds = Domains::Reviews::Rounds
      Messaging = Domains::Messaging::Dto
      COMMIT = /\A[0-9a-f]{40}\z/
      DISPATCHED = T.let([DispatchState::Delivered, DispatchState::Sending, DispatchState::Uncertain].freeze, T::Array[DispatchState])

      sig do
        params(herdr: Adapters::Herdr::Client, evidence: Adapters::Git::Evidence, callback_session: CallbackSession, rounds: Rounds,
               verdicts: Domains::Reviews::Verdicts, catalog: Domains::Workflows::Catalog, transitions: Domains::Workflows::Transitions,
               phase_prompts: Domains::Workflows::PhasePrompts, queue_release: QueueRelease, jobs: Platform::Jobs::Store, lock: Platform::Lock).void
      end
      def initialize(herdr:, evidence:, callback_session: CallbackSession.new, rounds: Rounds.new, verdicts: Domains::Reviews::Verdicts.new,
                     catalog: Domains::Workflows::Catalog.new, transitions: Domains::Workflows::Transitions.new,
                     phase_prompts: Domains::Workflows::PhasePrompts.new, queue_release: QueueRelease.new, jobs: Platform::Jobs::Store.new,
                     lock: Platform::Lock.new)
        @verify_settled = T.let(VerifySettled.new(herdr: herdr), VerifySettled)
        @evidence = evidence
        @callback_session = callback_session
        @rounds = rounds
        @verdicts = verdicts
        @catalog = catalog
        @transitions = transitions
        @phase_prompts = phase_prompts
        @queue_release = queue_release
        @jobs = jobs
        @lock = lock
      end

      # Returns the workflow id, or the review id of a replayed result.
      sig { params(caller: CallbackSession::Caller, generation: Integer, review_commit: String, verdict: String).returns(String) }
      def call(caller:, generation:, review_commit:, verdict:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          result = Verdict.try_deserialize(verdict)
          raise ArgumentError, "Exact review result required" unless result && review_commit.match?(COMMIT)

          session = @callback_session.call(caller: caller, generation: generation, role: Role::Reviewer)
          workflow_id = session.workflow_id or raise ArgumentError, Rounds::MALFORMED
          recorded = @rounds.find_decided(workflow_id: workflow_id, review_commit: review_commit, verdict: result)
          next recorded.id if recorded

          @lock.call(key: workflow_id) { finish(session, workflow_id, generation, review_commit, result) }
          workflow_id
        end
      end

      sig { params(session: Session, workflow_id: String, generation: Integer, review_commit: String, verdict: Verdict).void }
      private def finish(session, workflow_id, generation, review_commit, verdict)
        workflow = @catalog.find(id: workflow_id) or raise ArgumentError, Rounds::MALFORMED
        current_phase = workflow.effective_phase
        gate = Gate.values.find { |candidate| candidate.review_phase == current_phase }
        raise ArgumentError, "Review lock required" unless gate

        review = @rounds.latest(workflow_id: workflow_id, gate: gate) or raise ArgumentError, Rounds::MALFORMED
        raise ArgumentError, "Undispatched review" unless DISPATCHED.include?(review.dispatch_state) && review.verdict.nil?
        raise ArgumentError, "Reviewer configuration changed" unless session.configuration.serialize == review.reviewer_configuration.serialize

        prompt_effect_proved!(review) if review.dispatch_state != DispatchState::Delivered
        @verify_settled.call(session: session)
        configuration = session.configuration
        @evidence.review(worktree: worktree(workflow), target_commit: review.target_commit, review_path: review.review_path, review_commit: review_commit,
                         verdict: verdict.serialize, reviewer: Adapters::Git::Dto::ReviewerIdentity.new(provider: configuration.provider, model: configuration.model,
                                                                                                        family: configuration.family))
        phase = next_phase(gate, review, verdict)
        Platform::Transaction.new.call { record(workflow, review, session, generation, review_commit, verdict, phase) }
      end

      # An undelivered prompt counts only when its effect began and its lease ended.
      sig { params(review: Review).void }
      private def prompt_effect_proved!(review)
        job = @jobs.find_by_key(dispatch_key: "review:#{review.id}")
        raise ArgumentError, "Review prompt effect unproved" unless job&.effect_started_at

        lease_expires_at = job.lease_expires_at
        raise ArgumentError, "Review prompt lease still live" if job.status == Platform::Jobs::Dto::JobStatus::Running && lease_expires_at && lease_expires_at > Time.now
      end

      sig { params(gate: Gate, review: Review, verdict: Verdict).returns(Phase) }
      private def next_phase(gate, review, verdict)
        case verdict
        when Verdict::Approve then gate.human_approval_phase || Phase::PrReady
        when Verdict::ChangesRequested then review.round >= Rounds::MAX_ROUNDS ? Phase::Blocked : gate.writing_phase
        else T.absurd(verdict)
        end
      end

      sig { params(workflow: Workflow, review: Review, session: Session, generation: Integer, review_commit: String, verdict: Verdict, phase: Phase).void }
      private def record(workflow, review, session, generation, review_commit, verdict, phase)
        Platform::Unwrap.call(@verdicts.record(review_id: review.id, review_commit: review_commit, verdict: verdict))
        prompt_job = @jobs.find_by_key(dispatch_key: "review:#{review.id}")
        @jobs.close_reconciled(id: prompt_job.id) if prompt_job
        if review.dispatch_state != DispatchState::Delivered
          details = Domains::Reviews::Dto::ReviewReceiptAudit.new(review_id: review.id, target_commit: review.target_commit, review_commit: review_commit,
                                                                  session_id: session.id, generation: generation)
          Platform::Audit::Log.new.record(event_key: "review:receipt:#{review.id}", action: "verified_review_prompt_reconciliation", details: details)
        end
        version = workflow.version
        blocker = phase == Phase::Blocked ? "Three review rounds requested changes" : nil
        Platform::Unwrap.call(@transitions.enter(workflow_id: workflow.id, phase: phase, expected_version: version, paused_commit: review_commit, blocker: blocker))
        @queue_release.call(workflow_id: workflow.id, version: version + 1)
        @phase_prompts.enqueue(workflow_id: workflow.id, version: version + 1) if verdict == Verdict::ChangesRequested && phase != Phase::Blocked
        message = Messaging::OutgoingMessage.new(
          channel_id: workflow.channel_id, thread_id: workflow.thread_id, bot: Messaging::Bot::Worker, role: Messaging::SpeakerRole::Reviewer,
          body: "Review #{verdict.serialize} for #{review.target_commit}; committed at #{review_commit}.", key: "review:result:#{review.id}"
        )
        Platform::Unwrap.call(Domains::Messaging::Outbox.new.enqueue(message: message))
      end

      sig { params(workflow: Workflow).returns(Adapters::Git::Dto::WorktreeRef) }
      private def worktree(workflow) = Adapters::Git::Dto::WorktreeRef.new(worktree_path: workflow.worktree_path, branch: workflow.branch)
    end
  end
end
