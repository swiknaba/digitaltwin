# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    class Coordinator
      extend T::Sig

      PHASES = T.let({ "spec" => "spec_writing", "plan" => "plan_writing", "implementation" => "implementation" }.freeze, T::Hash[String, String])
      Row = T.type_alias { T::Hash[Symbol, Object] }
      Identifier = T.type_alias { String }
      Configuration = T.type_alias { T::Hash[String, Object] }
      Workflows = Domains::Workflows
      Workflow = Workflows::Dto::WorkflowView
      Session = Domains::Sessions::Dto::SessionView
      Role = Domains::Sessions::Dto::SessionRole

      sig do
        params(db: Sequel::Database, herdr: Adapters::Herdr::Client,
               evidence: Adapters::Git::Evidence, routing: Domains::Commander::Routing,
               policy: Domains::Workflows::Policy).void
      end
      def initialize(db, herdr:, evidence:, routing:, policy: Domains::Workflows::Policy.new)
        @db = db
        @herdr = herdr
        @evidence = evidence
        @routing = routing
        @policy = policy
        @lock = T.let(Platform::Lock.new, Platform::Lock)
        @catalog = T.let(Workflows::Catalog.new, Workflows::Catalog)
        @transitions = T.let(Workflows::Transitions.new, Workflows::Transitions)
        @queued_messages = T.let(Workflows::QueuedMessages.new, Workflows::QueuedMessages)
        @registry = T.let(Domains::Sessions::Registry.new, Domains::Sessions::Registry)
      end

      sig { params(token: String, generation: Integer, kind: String, commit: String).returns(Identifier) }
      def ready(token:, generation:, kind:, commit:)
        raise ArgumentError, "Artifact kind/commit required" unless PHASES.key?(kind) && commit.match?(/\A[0-9a-f]{40}\z/)

        ready_session(session_id: session(token, generation, Role::Writer).id, generation: generation, kind: kind, commit: commit)
      end

      sig { params(session_id: String, generation: Integer, kind: String, commit: String).returns(Identifier) }
      def ready_session(session_id:, generation:, kind:, commit:)
        raise ArgumentError, "Artifact kind/commit required" unless PHASES.key?(kind) && commit.match?(/\A[0-9a-f]{40}\z/)

        s = checked_session(session_id, generation, Role::Writer)
        workflow_id = workflow_id!(s)
        @lock.call(key: workflow_id) do
          w = workflow!(workflow_id)
          old = @db[:reviews][workflow_id: w.id, gate: kind, target_commit: commit]
          return old[:id] if old

          gate = Workflows::Dto::Gate.deserialize(kind)
          raise ArgumentError, "Writer phase required" unless w.effective_phase == gate.writing_phase && w.archived_at.nil?

          settled!(s)
          path = kind == "implementation" ? nil : "docs/#{kind}.md"
          @evidence.artifact(worktree: worktree!(w), commit: commit, path: path)
          round = (@db[:reviews].where(workflow_id: w.id, gate: kind).max(:round) || 0) + 1
          raise ArgumentError, "Review rounds exhausted" if round > 3

          base = kind == "implementation" ? @evidence.base(worktree: worktree!(w), commit: commit) : nil
          reviewer = @registry.active(workflow_id: w.id, role: Role::Reviewer).first
          raise ArgumentError, "Reviewer missing/diversity violated" unless reviewer

          reviewer_configuration = reviewer.configuration
          same_provider = reviewer_configuration.provider == s.configuration.provider
          same_family = reviewer_configuration.family == s.configuration.family
          raise ArgumentError, "Reviewer missing/diversity violated" if same_provider || same_family

          @db.transaction do
            id = @db[:reviews].insert(id: Platform::HumanId.call(prefix: "review"), workflow_id: w.id, gate: kind, round: round, target_commit: commit, base_commit: base,
                                      review_path: "docs/review.md", reviewer_configuration: Sequel.pg_jsonb(reviewer_configuration.serialize))
            ref = Workflows::Dto::ArtifactRef.new(commit: commit, path: path)
            Platform::Unwrap.call(@transitions.record_artifact(workflow_id: w.id, gate: gate, ref: ref, expected_version: w.version))
            Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::ReviewPrompt, payload: Dto::ReviewPromptJob.new(review_id: id), dispatch_key: "review:#{id}")
            id
          end
        end
      end

      sig { params(token: String, generation: Integer, review_commit: String, verdict: String).returns(Identifier) }
      def finish(token:, generation:, review_commit:, verdict:)
        raise ArgumentError, "Exact review result required" unless %w[approve changes_requested].include?(verdict) && review_commit.match?(/\A[0-9a-f]{40}\z/)

        finish_session(session_id: session(token, generation, Role::Reviewer).id, generation: generation, review_commit: review_commit, verdict: verdict)
      end

      sig { params(session_id: String, generation: Integer, review_commit: String, verdict: String).returns(Identifier) }
      def finish_session(session_id:, generation:, review_commit:, verdict:)
        raise ArgumentError, "Exact review result required" unless %w[approve changes_requested].include?(verdict) && review_commit.match?(/\A[0-9a-f]{40}\z/)

        s = checked_session(session_id, generation, Role::Reviewer)
        workflow_id = workflow_id!(s)
        old = @db[:reviews][workflow_id: workflow_id, review_commit: review_commit, verdict: verdict]
        return old[:id] if old

        @lock.call(key: workflow_id) do
          w = workflow!(workflow_id)
          current_phase = w.effective_phase
          gate = Workflows::Dto::Gate.values.find { |candidate| candidate.review_phase == current_phase }
          raise ArgumentError, "Review lock required" unless gate

          kind = gate.serialize

          record = row!(@db[:reviews].where(workflow_id: workflow_id, gate: kind).order(Sequel.desc(:round)).first)
          raise ArgumentError, "Undispatched review" unless %w[delivered sending uncertain].include?(row_string!(record, :dispatch_state)) && row_optional_string(record, :verdict).nil?
          raise ArgumentError, "Reviewer configuration changed" unless s.configuration.serialize == configuration!(record, :reviewer_configuration)

          if row_string!(record, :dispatch_state) != "delivered"
            job = Platform::Jobs::Store.new.find_by_key(dispatch_key: "review:#{row_identifier!(record, :id)}")
            raise ArgumentError, "Review prompt effect unproved" unless job&.effect_started_at

            lease_expires_at = job.lease_expires_at
            raise ArgumentError, "Review prompt lease still live" if job.status == Platform::Jobs::Dto::JobStatus::Running && lease_expires_at && lease_expires_at > Time.now
          end
          settled!(s)
          @evidence.review(worktree: worktree!(w), target_commit: review_evidence!(record, :target_commit), review_path: review_evidence!(record, :review_path),
                           review_commit: review_commit, verdict: verdict, reviewer: reviewer_identity(s.configuration))
          phase = if verdict == "approve"
                    kind == "implementation" ? "pr_ready" : "#{kind}_human_approval"
                  elsif row_integer!(record, :round) >= 3
                    "blocked"
                  else
                    PHASES.fetch(kind)
                  end
          @db.transaction do
            @db[:reviews].where(id: row_identifier!(record, :id)).update(review_commit: review_commit, verdict: verdict, dispatch_state: "delivered")
            jobs = Platform::Jobs::Store.new
            prompt_job = jobs.find_by_key(dispatch_key: "review:#{row_identifier!(record, :id)}")
            jobs.close_reconciled(id: prompt_job.id) if prompt_job
            if row_string!(record, :dispatch_state) != "delivered"
              details = Dto::ReviewReceiptAudit.new(review_id: row_identifier!(record, :id), target_commit: row_string!(record, :target_commit), review_commit: review_commit,
                                                    session_id: s.id, generation: generation)
              Platform::Audit::Log.new.record(event_key: "review:receipt:#{row_identifier!(record, :id)}", action: "verified_review_prompt_reconciliation", details: details)
            end
            version = w.version
            Platform::Unwrap.call(@transitions.enter(workflow_id: workflow_id, phase: Workflows::Dto::Phase.deserialize(phase), expected_version: version,
                                                     paused_commit: review_commit, blocker: phase == "blocked" ? "Three review rounds requested changes" : nil))
            queue_release(workflow_id, version + 1)
            if verdict == "changes_requested" && phase != "blocked"
              jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::WorkflowPhasePrompt, payload: Domains::Workflows::Dto::PhasePromptJob.new(workflow_id: workflow_id, version: version + 1),
                           dispatch_key: "workflow:phase:#{workflow_id}:#{version + 1}")
            end
            message = Domains::Messaging::Dto::OutgoingMessage.new(
              channel_id: w.channel_id,
              thread_id: w.thread_id,
              bot: Domains::Messaging::Dto::Bot::Worker,
              role: Domains::Messaging::Dto::SpeakerRole::Reviewer,
              body: "Review #{verdict} for #{row_string!(record, :target_commit)}; committed at #{review_commit}.",
              key: "review:result:#{row_identifier!(record, :id)}"
            )
            Platform::Unwrap.call(Domains::Messaging::Outbox.new.enqueue(message: message))
          end
        end
        workflow_id
      end

      sig { params(workflow_id: String, version: Integer).returns(String) }
      def queue_release(workflow_id, version)
        Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::ReviewRelease, payload: Dto::ReleaseJob.new(workflow_id: workflow_id), dispatch_key: "review:release:#{workflow_id}:#{version}")
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def release_job(job:)
        release(Dto::ReleaseJob.from_hash(job.payload, true).workflow_id)
        Platform::Jobs::Dto::Decision.complete
      end

      sig { params(workflow_id: String).returns(T.nilable(String)) }
      def release(workflow_id)
        w = workflow!(workflow_id)
        return unless w.phase.writing?

        transient = T.let(nil, T.nilable(Adapters::Mattermost::Errors::RequestFailed))
        jobs = Platform::Jobs::Store.new
        @queued_messages.pending(workflow_id: workflow_id).each do |row|
          begin
            result = @routing.route(inbox_id: row.inbox_id)
            @queued_messages.remove(id: row.id) if route_dispatched?(result)
          rescue ArgumentError, Adapters::Mattermost::Errors::RequestFailed => error
            if error.is_a?(Adapters::Mattermost::Errors::RequestFailed) && ![403, 404].include?(error.status)
              transient = error
              break
            end
            # Retain invalid sources for reconciliation; one revoked message
            # must not prevent other verified instructions from being released.
            Platform::Audit::Log.new.record_once(event_key: "release:invalid:#{row.id}", action: "release_source_rejected",
                                                 details: Dto::ReleaseRejectedAudit.new(workflow_id: workflow_id, inbox_id: row.inbox_id))
          end
        end
        @db[:followups].where(workflow_id: workflow_id, status: "queued").each do |row|
          job = jobs.find_by_key(dispatch_key: "followup:#{row[:id]}")
          jobs.requeue_blocked(id: job.id) if job
        end
        raise transient if transient
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        record = row!(@db[:reviews][id: Dto::ReviewPromptJob.from_hash(job.payload, true).review_id])
        @lock.call(key: row_string!(record, :workflow_id)) do
          return Platform::Jobs::Dto::Decision.complete if record[:dispatch_state] == "delivered"
          raise ArgumentError, "Uncertain review prompt" unless record[:dispatch_state] == "queued"

          return Platform::Jobs::Dto::Decision.block("Live review dispatch evidence required") unless @policy.dispatch_allowed?

          w = workflow!(row_string!(record, :workflow_id))
          return Platform::Jobs::Dto::Decision.defer("Paused review") if w.phase == Workflows::Dto::Phase::Paused

          raise ArgumentError, "Review phase changed" unless w.phase.serialize == "#{record[:gate]}_review"

          @evidence.artifact(worktree: worktree!(w), commit: row_string!(record, :target_commit), path: artifact_path!(w, row_string!(record, :gate)))
          s = @registry.active(workflow_id: w.id, role: Role::Reviewer).first
          raise ArgumentError, "Malformed durable review record" unless s
          raise ArgumentError, "Reviewer configuration changed" unless s.configuration.serialize == configuration!(record, :reviewer_configuration)

          live = @herdr.pane(s.pane_id)
          if live.agent_status == Adapters::Herdr::Dto::AgentStatus::Working && live.agent_session&.serialize == runtime_identity!(s)
            return Platform::Jobs::Dto::Decision.defer("Reviewer busy")
          end

          settled!(s)
          @db[:reviews].where(id: record[:id]).update(dispatch_state: "sending")
          begin
            raise IOError, "Dispatch lease lost" unless job.lease.begin_effect

            prompt = "Review #{record[:gate]} target #{record[:target_commit]}, base #{record[:base_commit]}. " \
                     "Change only #{record[:review_path]}; append Target, Provider, Model, Family, Verdict and Reviewed-at (UTC ISO8601) fields. " \
                     "Report the exact review commit via review-ready. Do not change the artifact or start sessions."
            @herdr.prompt(pane_id: s.pane_id, text: prompt)
            @db[:reviews].where(id: record[:id]).update(dispatch_state: "delivered")
          rescue StandardError
            @db[:reviews].where(id: record[:id]).update(dispatch_state: "uncertain")
            raise
          end
          Platform::Jobs::Dto::Decision.complete
        end
      end

      sig { params(token: String, generation: Integer, role: Role).returns(Session) }
      private def session(token, generation, role)
        s = @registry.find_by_credential(digest: Digest::SHA256.hexdigest(token), generation: generation)
        raise ArgumentError, "Malformed durable review record" unless s && s.role == role

        latest = @registry.latest_generation(workflow_id: workflow_id!(s), role: role)
        raise ArgumentError, "Invalid callback session" unless s.credential_expires_at > Time.now && latest == generation

        s
      end

      sig { params(id: String, generation: Integer, role: Role).returns(Session) }
      private def checked_session(id, generation, role)
        s = @registry.find(id: id)
        raise ArgumentError, "Malformed durable review record" unless s && s.generation == generation && s.active && s.role == role

        latest = @registry.latest_generation(workflow_id: workflow_id!(s), role: role)
        raise ArgumentError, "Stale callback session" unless latest == generation && s.credential_expires_at > Time.now

        s
      end

      sig { params(session: Session).void }
      private def settled!(session)
        live = @herdr.pane(session.pane_id)
        raise ArgumentError, "Session not settled or replaced" unless live.agent_session&.serialize == runtime_identity!(session) && live.agent_status.settled?
      end

      # Review sessions are always started, so a missing identity is a malformed record.
      sig { params(session: Session).returns(T::Hash[String, String]) }
      private def runtime_identity!(session)
        identity = session.runtime_identity
        raise ArgumentError, "Malformed durable review record" unless identity

        identity.serialize
      end

      sig { params(session: Session).returns(String) }
      private def workflow_id!(session)
        session.workflow_id or raise ArgumentError, "Malformed durable review record"
      end

      sig { params(row: Object).returns(Row) }
      private def row!(row)
        raise ArgumentError, "Malformed durable review record" unless row.is_a?(Hash)

        typed = T.let({}, Row)
        row.each do |key, value|
          raise ArgumentError, "Malformed durable review record" unless key.is_a?(Symbol)

          typed[key] = value
        end
        typed
      end

      sig { params(row: Row, key: Symbol).returns(String) }
      private def row_string!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Malformed durable review record" }
        raise ArgumentError, "Malformed durable review record" unless value.is_a?(String)

        value
      end

      sig { params(row: Row, key: Symbol).returns(Identifier) }
      private def row_identifier!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Malformed durable review record" }
        raise ArgumentError, "Malformed durable review record" unless value.is_a?(String)

        value
      end

      sig { params(row: Row, key: Symbol).returns(Integer) }
      private def row_integer!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Malformed durable review record" }
        raise ArgumentError, "Malformed durable review record" unless value.is_a?(Integer)

        value
      end

      sig { params(row: Row, key: Symbol).returns(T.nilable(String)) }
      private def row_optional_string(row, key)
        value = row.fetch(key) { return nil }
        raise ArgumentError, "Malformed durable review record" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(workflow_id: String).returns(Workflow) }
      private def workflow!(workflow_id)
        @catalog.find(id: workflow_id) or raise ArgumentError, "Malformed durable review record"
      end

      sig { params(workflow: Workflow).returns(Adapters::Git::Dto::WorktreeRef) }
      private def worktree!(workflow)
        Adapters::Git::Dto::WorktreeRef.new(worktree_path: workflow.worktree_path, branch: workflow.branch)
      end

      sig { params(record: Row, key: Symbol).returns(String) }
      private def review_evidence!(record, key)
        value = row_optional_string(record, key)
        raise ArgumentError, "Invalid review evidence" unless value

        value
      end

      sig { params(row: Row, key: Symbol).returns(Configuration) }
      private def configuration!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Malformed durable review record" }
        configuration_values = Hash.try_convert(value)
        raise ArgumentError, "Malformed durable review record" unless configuration_values

        configuration = T.let({}, Configuration)
        configuration_values.each do |configuration_key, configuration_value|
          raise ArgumentError, "Malformed durable review record" unless configuration_key.is_a?(String)

          configuration[configuration_key] = configuration_value
        end
        configuration
      end

      sig { params(configuration: Workflows::Dto::RoleConfig).returns(Adapters::Git::Dto::ReviewerIdentity) }
      private def reviewer_identity(configuration)
        Adapters::Git::Dto::ReviewerIdentity.new(provider: configuration.provider, model: configuration.model, family: configuration.family)
      end

      sig { params(result: Object).returns(T::Boolean) }
      private def route_dispatched?(result)
        result.is_a?(Hash) && (result.key?(:id) || result.key?("id"))
      end

      sig { params(workflow: Workflow, gate: String).returns(T.nilable(String)) }
      private def artifact_path!(workflow, gate)
        ref = workflow.artifacts.fetch(Workflows::Dto::Gate.deserialize(gate)) or raise ArgumentError, "Malformed workflow record"
        ref.path
      end
    end
  end
end
