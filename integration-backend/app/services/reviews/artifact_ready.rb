# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    # A Writer reports an exact artifact commit. Under the workflow lock this
    # verifies the settled Writer, the artifact evidence and a diverse
    # Reviewer, then opens the next review round, enters the review phase and
    # queues the reviewer prompt in one transaction. A replay of the same
    # commit returns the round it opened.
    class ArtifactReady
      extend T::Sig

      Gate = Domains::Workflows::Dto::Gate
      Role = Domains::Sessions::Dto::SessionRole
      Session = Domains::Sessions::Dto::SessionView
      Workflow = Domains::Workflows::Dto::WorkflowView
      Rounds = Domains::Reviews::Rounds
      COMMIT = /\A[0-9a-f]{40}\z/
      REVIEW_PATH = "docs/review.md"

      sig do
        params(herdr: Adapters::Herdr::Client, evidence: Adapters::Git::Evidence, callback_session: CallbackSession, rounds: Rounds,
               registry: Domains::Sessions::Registry, catalog: Domains::Workflows::Catalog, transitions: Domains::Workflows::Transitions,
               jobs: Platform::Jobs::Store, lock: Platform::Lock).void
      end
      def initialize(herdr:, evidence:, callback_session: CallbackSession.new, rounds: Rounds.new, registry: Domains::Sessions::Registry.new,
                     catalog: Domains::Workflows::Catalog.new, transitions: Domains::Workflows::Transitions.new, jobs: Platform::Jobs::Store.new,
                     lock: Platform::Lock.new)
        @verify_settled = T.let(VerifySettled.new(herdr: herdr), VerifySettled)
        @evidence = evidence
        @callback_session = callback_session
        @rounds = rounds
        @registry = registry
        @catalog = catalog
        @transitions = transitions
        @jobs = jobs
        @lock = lock
      end

      # Returns the review id.
      sig { params(caller: CallbackSession::Caller, generation: Integer, kind: String, commit: String).returns(String) }
      def call(caller:, generation:, kind:, commit:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          gate = Gate.try_deserialize(kind)
          raise ArgumentError, "Artifact kind/commit required" unless gate && commit.match?(COMMIT)

          session = @callback_session.call(caller: caller, generation: generation, role: Role::Writer)
          workflow_id = session.workflow_id or raise ArgumentError, Rounds::MALFORMED
          @lock.call(key: workflow_id) { ready(session, workflow_id, gate, commit) }
        end
      end

      sig { params(session: Session, workflow_id: String, gate: Gate, commit: String).returns(String) }
      private def ready(session, workflow_id, gate, commit)
        workflow = @catalog.find(id: workflow_id) or raise ArgumentError, Rounds::MALFORMED
        opened = @rounds.find_for_target(workflow_id: workflow.id, gate: gate, target_commit: commit)
        return opened.id if opened
        raise ArgumentError, "Writer phase required" unless workflow.effective_phase == gate.writing_phase && workflow.archived_at.nil?

        @verify_settled.call(session: session)
        path = gate == Gate::Implementation ? nil : "docs/#{gate.serialize}.md"
        worktree = Adapters::Git::Dto::WorktreeRef.new(worktree_path: workflow.worktree_path, branch: workflow.branch)
        @evidence.artifact(worktree: worktree, commit: commit, path: path)
        raise ArgumentError, "Review rounds exhausted" if @rounds.next_round(workflow_id: workflow.id, gate: gate) > Rounds::MAX_ROUNDS

        base = gate == Gate::Implementation ? @evidence.base(worktree: worktree, commit: commit) : nil
        reviewer = diverse_reviewer(workflow, session)
        Platform::Transaction.new.call do
          review = Platform::Unwrap.call(@rounds.open(workflow_id: workflow.id, gate: gate, target_commit: commit, base_commit: base, review_path: REVIEW_PATH,
                                                      reviewer: reviewer))
          ref = Domains::Workflows::Dto::ArtifactRef.new(commit: commit, path: path)
          Platform::Unwrap.call(@transitions.record_artifact(workflow_id: workflow.id, gate: gate, ref: ref, expected_version: workflow.version))
          @jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::ReviewPrompt, payload: Domains::Reviews::Dto::ReviewPromptJob.new(review_id: review.id),
                        dispatch_key: "review:#{review.id}")
          review.id
        end
      end

      # The active Reviewer's configuration; it must differ from the Writer's
      # provider and model family.
      sig { params(workflow: Workflow, writer: Session).returns(Domains::Workflows::Dto::RoleConfig) }
      private def diverse_reviewer(workflow, writer)
        reviewer = @registry.active(workflow_id: workflow.id, role: Role::Reviewer).first
        raise ArgumentError, "Reviewer missing/diversity violated" unless reviewer

        configuration = reviewer.configuration
        same_provider = configuration.provider == writer.configuration.provider
        same_family = configuration.family == writer.configuration.family
        raise ArgumentError, "Reviewer missing/diversity violated" if same_provider || same_family

        configuration
      end
    end
  end
end
