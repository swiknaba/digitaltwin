# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    class Coordinator
      extend T::Sig

      PHASES = T.let({ "spec" => "spec_writing", "plan" => "plan_writing", "implementation" => "implementation" }.freeze, T::Hash[String, String])
      Row = T.type_alias { T::Hash[Symbol, Object] }
      Identifier = T.type_alias { T.any(String, Integer) }
      JsonObject = T.type_alias { T::Hash[String, Object] }
      Configuration = T.type_alias { T::Hash[String, Object] }

      sig do
        params(db: Sequel::Database, herdr: Domains::Sessions::Herdr,
               evidence: GitEvidence, routing: Domains::Commander::Routing,
               policy: Domains::Workflows::Policy).void
      end
      def initialize(db, herdr:, evidence:, routing:, policy: Domains::Workflows::Policy.new)
        @db = db
        @herdr = herdr
        @evidence = evidence
        @routing = routing
        @policy = policy
        @lock = T.let(Platform::Lock.new, Platform::Lock)
      end

      sig { params(token: String, generation: Integer, kind: String, commit: String).returns(Identifier) }
      def ready(token:, generation:, kind:, commit:)
        raise ArgumentError, "Artifact kind/commit required" unless PHASES.key?(kind) && commit.match?(/\A[0-9a-f]{40}\z/)

        ready_session(session_id: row_string!(session(token, generation, "writer"), :id), generation: generation, kind: kind, commit: commit)
      end

      sig { params(session_id: String, generation: Integer, kind: String, commit: String).returns(Identifier) }
      def ready_session(session_id:, generation:, kind:, commit:)
        raise ArgumentError, "Artifact kind/commit required" unless PHASES.key?(kind) && commit.match?(/\A[0-9a-f]{40}\z/)

        s = checked_session(session_id, generation, "writer")
        workflow_id = row_string!(s, :workflow_id)
        @lock.call(key: workflow_id) do
          w = row!(@db[:workflows][id: workflow_id])
          old = @db[:reviews][workflow_id: row_string!(w, :id), gate: kind, target_commit: commit]
          return old[:id] if old

          current_phase = phase_for(w)
          raise ArgumentError, "Writer phase required" unless current_phase == PHASES[kind] && row_optional_time(w, :archived_at).nil?

          settled!(s)
          path = kind == "implementation" ? nil : "docs/#{kind}.md"
          @evidence.artifact(evidence_workflow!(w), commit, path)
          round = (@db[:reviews].where(workflow_id: row_string!(w, :id), gate: kind).max(:round) || 0) + 1
          raise ArgumentError, "Review rounds exhausted" if round > 3

          base = kind == "implementation" ? @evidence.base(evidence_workflow!(w), commit) : nil
          reviewer_row = @db[:sessions][workflow_id: row_string!(w, :id), role: "reviewer", active: true]
          reviewer = reviewer_row && row!(reviewer_row)
          raise ArgumentError, "Reviewer missing/diversity violated" unless reviewer

          reviewer_configuration = configuration!(reviewer)
          writer_configuration = configuration!(s)
          same_provider = reviewer_configuration.fetch("provider") == writer_configuration.fetch("provider")
          same_family = reviewer_configuration.fetch("family") == writer_configuration.fetch("family")
          raise ArgumentError, "Reviewer missing/diversity violated" if same_provider || same_family

          @db.transaction do
            id = @db[:reviews].insert(workflow_id: row_string!(w, :id), gate: kind, round: round, target_commit: commit, base_commit: base,
                                      review_path: "docs/review.md", reviewer_configuration: Sequel.pg_jsonb(reviewer_configuration))
            refs = artifact_refs!(w).merge(kind => { "commit" => commit, "path" => path })
            changes = row_string!(w, :phase) == "paused" ? { saved_phase: "#{kind}_review", paused_commit: commit } : { phase: "#{kind}_review" }
            version = row_integer!(w, :version)
            @db[:workflows].where(id: row_string!(w, :id), version: version).update(**changes, artifacts: Sequel.pg_jsonb(refs), version: version + 1)
            Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::ReviewPrompt, payload: Dto::ReviewPromptJob.new(review_id: id), dispatch_key: "review:#{id}")
            id
          end
        end
      end

      sig { params(token: String, generation: Integer, review_commit: String, verdict: String).returns(Identifier) }
      def finish(token:, generation:, review_commit:, verdict:)
        raise ArgumentError, "Exact review result required" unless %w[approve changes_requested].include?(verdict) && review_commit.match?(/\A[0-9a-f]{40}\z/)

        finish_session(session_id: row_string!(session(token, generation, "reviewer"), :id), generation: generation, review_commit: review_commit, verdict: verdict)
      end

      sig { params(session_id: String, generation: Integer, review_commit: String, verdict: String).returns(Identifier) }
      def finish_session(session_id:, generation:, review_commit:, verdict:)
        raise ArgumentError, "Exact review result required" unless %w[approve changes_requested].include?(verdict) && review_commit.match?(/\A[0-9a-f]{40}\z/)

        s = checked_session(session_id, generation, "reviewer")
        workflow_id = row_string!(s, :workflow_id)
        old = @db[:reviews][workflow_id: workflow_id, review_commit: review_commit, verdict: verdict]
        return old[:id] if old

        @lock.call(key: workflow_id) do
          w = row!(@db[:workflows][id: workflow_id])
          current_phase = phase_for(w)
          kind = current_phase.delete_suffix("_review")
          raise ArgumentError, "Review lock required" unless PHASES.key?(kind) && current_phase.end_with?("_review")

          record = row!(@db[:reviews].where(workflow_id: workflow_id, gate: kind).order(Sequel.desc(:round)).first)
          raise ArgumentError, "Undispatched review" unless %w[delivered sending uncertain].include?(row_string!(record, :dispatch_state)) && row_optional_string(record, :verdict).nil?
          raise ArgumentError, "Reviewer configuration changed" unless configuration!(s) == configuration!(record, :reviewer_configuration)

          if row_string!(record, :dispatch_state) != "delivered"
            job = Platform::Jobs::Store.new.find_by_key(dispatch_key: "review:#{row_identifier!(record, :id)}")
            raise ArgumentError, "Review prompt effect unproved" unless job&.effect_started_at

            lease_expires_at = job.lease_expires_at
            raise ArgumentError, "Review prompt lease still live" if job.status == Platform::Jobs::Dto::JobStatus::Running && lease_expires_at && lease_expires_at > Time.now
          end
          settled!(s)
          @evidence.review(evidence_workflow!(w), evidence_record!(record), review_commit, verdict, review_configuration!(configuration!(s)))
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
              details = Dto::ReviewReceiptAudit.new(review_id: row_integer!(record, :id), target_commit: row_string!(record, :target_commit), review_commit: review_commit,
                                                    session_id: row_string!(s, :id), generation: generation)
              Platform::Audit::Log.new.record(event_key: "review:receipt:#{row_identifier!(record, :id)}", action: "verified_review_prompt_reconciliation", details: details)
            end
            changes = row_string!(w, :phase) == "paused" ? { saved_phase: phase, paused_commit: review_commit } : { phase: phase }
            version = row_integer!(w, :version)
            @db[:workflows].where(id: workflow_id, version: version).update(**changes, version: version + 1,
                                                                                       blocker: phase == "blocked" ? "Three review rounds requested changes" : nil)
            queue_release(workflow_id, version + 1)
            if verdict == "changes_requested" && phase != "blocked"
              jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::WorkflowPhasePrompt, payload: Domains::Workflows::Dto::PhasePromptJob.new(workflow_id: workflow_id, version: version + 1),
                           dispatch_key: "workflow:phase:#{workflow_id}:#{version + 1}")
            end
            Domains::Mattermost::Outbox.new.enqueue(channel_id: row_string!(w, :channel_id), thread_id: row_optional_string(w, :thread_id), bot: "worker", role: "reviewer",
                                                    body: "Review #{verdict} for #{row_string!(record, :target_commit)}; committed at #{review_commit}.", key: "review:result:#{row_identifier!(record, :id)}")
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
        w = row!(@db[:workflows][id: workflow_id])
        return unless PHASES.value?(row_string!(w, :phase))

        transient = T.let(nil, T.nilable(Domains::Mattermost::Client::Error))
        jobs = Platform::Jobs::Store.new
        @db[:queued_messages].where(workflow_id: workflow_id).order(:id).each do |row|
          begin
            result = @routing.route(inbox_id: row[:inbox_id])
            @db[:queued_messages].where(id: row[:id]).delete if route_dispatched?(result)
          rescue ArgumentError, Domains::Mattermost::Client::Error => error
            if error.is_a?(Domains::Mattermost::Client::Error) && ![403, 404].include?(error.status)
              transient = error
              break
            end
            # Retain invalid sources for reconciliation; one revoked message
            # must not prevent other verified instructions from being released.
            Platform::Audit::Log.new.record_once(event_key: "release:invalid:#{row[:id]}", action: "release_source_rejected",
                                                 details: Dto::ReleaseRejectedAudit.new(workflow_id: workflow_id, inbox_id: row[:inbox_id]))
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

          w = row!(@db[:workflows][id: row_string!(record, :workflow_id)])
          return Platform::Jobs::Dto::Decision.defer("Paused review") if w[:phase] == "paused"

          raise ArgumentError, "Review phase changed" unless w[:phase] == "#{record[:gate]}_review"

          @evidence.artifact(evidence_workflow!(w), row_string!(record, :target_commit), artifact_path!(w, row_string!(record, :gate)))
          s = row!(@db[:sessions][workflow_id: row_string!(w, :id), role: "reviewer", active: true])
          raise ArgumentError, "Reviewer configuration changed" unless configuration!(s) == configuration!(record, :reviewer_configuration)

          live = @herdr.get(row_string!(s, :pane_id))
          if live["agent_status"] == "working" && live["agent_session"] == row_json_object!(s, :runtime_identity)
            return Platform::Jobs::Dto::Decision.defer("Reviewer busy")
          end

          settled!(s)
          @db[:reviews].where(id: record[:id]).update(dispatch_state: "sending")
          begin
            raise IOError, "Dispatch lease lost" unless job.lease.begin_effect

            prompt = "Review #{record[:gate]} target #{record[:target_commit]}, base #{record[:base_commit]}. " \
                     "Change only #{record[:review_path]}; append Target, Provider, Model, Family, Verdict and Reviewed-at (UTC ISO8601) fields. " \
                     "Report the exact review commit via review-ready. Do not change the artifact or start sessions."
            @herdr.prompt(row_string!(s, :pane_id), prompt)
            @db[:reviews].where(id: record[:id]).update(dispatch_state: "delivered")
          rescue StandardError
            @db[:reviews].where(id: record[:id]).update(dispatch_state: "uncertain")
            raise
          end
          Platform::Jobs::Dto::Decision.complete
        end
      end

      private

      sig { params(token: String, generation: Integer, role: String).returns(Row) }
      def session(token, generation, role)
        raw = @db[:sessions][credential_digest: Digest::SHA256.hexdigest(token), generation: generation, active: true, role: role]
        s = row!(raw)
        latest = @db[:sessions].where(workflow_id: row_string!(s, :workflow_id), role: role).max(:generation)
        raise ArgumentError, "Invalid callback session" unless row_time!(s, :credential_expires_at) > Time.now && latest == generation

        s
      end
      sig { params(id: String, generation: Integer, role: String).returns(Row) }
      def checked_session(id, generation, role)
        raw = @db[:sessions][id: id, generation: generation, active: true, role: role]
        s = row!(raw)
        latest = @db[:sessions].where(workflow_id: row_string!(s, :workflow_id), role: role).max(:generation)
        raise ArgumentError, "Stale callback session" unless latest == generation && row_time!(s, :credential_expires_at) > Time.now

        s
      end
      sig { params(session: Row).void }
      def settled!(session)
        live = @herdr.get(row_string!(session, :pane_id))
        runtime_identity = row_json_object!(session, :runtime_identity)
        raise ArgumentError, "Session not settled or replaced" unless live["agent_session"] == runtime_identity && %w[idle done].include?(live["agent_status"])
      end

      sig { params(row: Object).returns(Row) }
      def row!(row)
        raise ArgumentError, "Malformed durable review record" unless row.is_a?(Hash)

        typed = T.let({}, Row)
        row.each do |key, value|
          raise ArgumentError, "Malformed durable review record" unless key.is_a?(Symbol)

          typed[key] = value
        end
        typed
      end

      sig { params(row: Row, key: Symbol).returns(String) }
      def row_string!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Malformed durable review record" }
        raise ArgumentError, "Malformed durable review record" unless value.is_a?(String)

        value
      end

      sig { params(row: Row, key: Symbol).returns(Identifier) }
      def row_identifier!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Malformed durable review record" }
        raise ArgumentError, "Malformed durable review record" unless value.is_a?(String) || value.is_a?(Integer)

        value
      end

      sig { params(row: Row, key: Symbol).returns(JsonObject) }
      def row_json_object!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Malformed durable review record" }
        json_object = Hash.try_convert(value)
        raise ArgumentError, "Malformed durable review record" unless json_object

        object = T.let({}, JsonObject)
        json_object.each do |object_key, object_value|
          raise ArgumentError, "Malformed durable review record" unless object_key.is_a?(String)

          object[object_key] = object_value
        end
        object
      end

      sig { params(row: Row, key: Symbol).returns(Time) }
      def row_time!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Malformed durable review record" }
        raise ArgumentError, "Malformed durable review record" unless value.is_a?(Time)

        value
      end

      sig { params(row: Row, key: Symbol).returns(T.nilable(Time)) }
      def row_optional_time(row, key)
        value = row.fetch(key) { return nil }
        raise ArgumentError, "Malformed durable review record" unless value.nil? || value.is_a?(Time)

        value
      end

      sig { params(row: Row, key: Symbol).returns(Integer) }
      def row_integer!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Malformed durable review record" }
        raise ArgumentError, "Malformed durable review record" unless value.is_a?(Integer)

        value
      end

      sig { params(row: Row, key: Symbol).returns(T.nilable(String)) }
      def row_optional_string(row, key)
        value = row.fetch(key) { return nil }
        raise ArgumentError, "Malformed durable review record" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(workflow: Row).returns(String) }
      def phase_for(workflow)
        row_string!(workflow, row_string!(workflow, :phase) == "paused" ? :saved_phase : :phase)
      end

      sig { params(workflow: Row).returns(GitEvidence::Workflow) }
      def evidence_workflow!(workflow)
        { worktree_path: row_string!(workflow, :worktree_path), artifacts: artifact_refs!(workflow) }
      end

      sig { params(record: Row).returns(GitEvidence::ReviewRecord) }
      def evidence_record!(record)
        values = T.let({}, GitEvidence::ReviewRecord)
        %i[target_commit review_path review_commit gate].each do |key|
          values[key] = row_optional_string(record, key)
        end
        values
      end

      sig { params(workflow: Row).returns(GitEvidence::ArtifactRefs) }
      def artifact_refs!(workflow)
        raw = workflow.fetch(:artifacts) { raise ArgumentError, "Malformed workflow record" }
        artifact_refs = Hash.try_convert(raw)
        raise ArgumentError, "Malformed workflow record" unless artifact_refs

        refs = T.let({}, GitEvidence::ArtifactRefs)
        artifact_refs.each do |kind, raw_ref|
          ref = Hash.try_convert(raw_ref)
          raise ArgumentError, "Malformed workflow record" unless kind.is_a?(String) && ref

          commit = ref.fetch("commit") { raise ArgumentError, "Malformed workflow record" }
          path = ref.fetch("path") { raise ArgumentError, "Malformed workflow record" }
          raise ArgumentError, "Malformed workflow record" unless commit.nil? || commit.is_a?(String)
          raise ArgumentError, "Malformed workflow record" unless path.nil? || path.is_a?(String)

          refs[kind] = { "commit" => commit, "path" => path }
        end
        refs
      end

      sig { params(row: Row, key: Symbol).returns(Configuration) }
      def configuration!(row, key = :configuration)
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

      sig { params(row: Row, key: String).returns(String) }
      def configuration_value!(row, key)
        value = configuration!(row).fetch(key) { raise ArgumentError, "Malformed durable review record" }
        raise ArgumentError, "Malformed durable review record" unless value.is_a?(String)

        value
      end

      sig { params(configuration: Configuration).returns(GitEvidence::Configuration) }
      def review_configuration!(configuration)
        required = T.let({}, GitEvidence::Configuration)
        %w[provider model family].each do |key|
          value = configuration.fetch(key) { raise ArgumentError, "Malformed durable review record" }
          raise ArgumentError, "Malformed durable review record" unless value.is_a?(String)

          required[key] = value
        end
        required
      end

      sig { params(result: Object).returns(T::Boolean) }
      def route_dispatched?(result)
        result.is_a?(Hash) && (result.key?(:id) || result.key?("id"))
      end

      sig { params(workflow: Row, gate: String).returns(T.nilable(String)) }
      def artifact_path!(workflow, gate)
        artifact_refs!(workflow).fetch(gate) { raise ArgumentError, "Malformed workflow record" }.fetch("path")
      end
    end
  end
end
