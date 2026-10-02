# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    class Coordinator
      extend T::Sig

      Job = T.type_alias { T::Hash[Symbol, Object] }
      # Persisted inbox IDs are integers; adapters may provide a string form
      # that Commander::Source resolves and verifies at the authority boundary.
      InboxId = T.type_alias { T.any(Integer, String) }

      sig do
        params(
          db: Sequel::Database,
          source: Domains::Commander::Source,
          herdr: Domains::Sessions::Herdr,
          evidence: Domains::Reviews::GitEvidence,
          reviews: Domains::Reviews::Coordinator,
          sessions: Domains::Sessions::Lifecycle,
          policy: Policy
        ).void
      end
      def initialize(db, source:, herdr:, evidence:, reviews:, sessions:, policy: Policy.new)
        @db = db
        @source = source
        @herdr = herdr
        @evidence = evidence
        @reviews = reviews
        @sessions = sessions
        @policy = policy
        @lock = T.let(Lock.new(db), Lock)
      end

      sig { params(inbox_id: InboxId, workflow_id: String, action: String, expected_version: Integer).returns(String) }
      def control(inbox_id:, workflow_id:, action:, expected_version:)
        raise ArgumentError, "Unsupported workflow action" unless %w[pause resume finish cancel].include?(action)

        w = @db[:workflows][id: workflow_id] or raise ArgumentError, "Missing workflow"
        @source.human(inbox_id, destination: w[:channel_id])
        @lock.call(workflow_id) do
          w = @db[:workflows][id: workflow_id]
          raise ArgumentError, "Workflow version changed" unless w[:version] == expected_version && !w[:archived_at]

          changes = T.let({}, T::Hash[Symbol, Object])
          case action
          when "pause"
            raise ArgumentError, "Cannot pause this phase" if %w[paused closed cancelled blocked].include?(w[:phase])

            changes = { phase: "paused", saved_phase: w[:phase], paused_commit: @evidence.head(w) }
          when "resume"
            raise ArgumentError, "Not paused" unless w[:phase] == "paused" && w[:saved_phase] && w[:saved_phase] != "blocked"

            live_role = w[:saved_phase].end_with?("_review") ? "reviewer" : "writer"
            validate_sessions(w, live_role)
            raise ArgumentError, "Paused revision changed without verified callback" unless @evidence.current(w) == w[:paused_commit]

            changes = { phase: w[:saved_phase], saved_phase: nil, paused_commit: nil }
          when "finish"
            raise ArgumentError, "Only delivered workflow may finish" unless w[:phase] == "done"

            validate_sessions(w)
            changes = { phase: "closed" }
          when "cancel"
            raise ArgumentError, "Already closed" if %w[closed cancelled].include?(w[:phase])

            validate_sessions(w)
            changes = { phase: "cancelled" }
          end
          @db.transaction do
            @db[:workflows].where(id: workflow_id, version: expected_version).update(**changes, version: expected_version + 1)
            if action == "resume" && %w[spec_writing plan_writing implementation].include?(changes[:phase])
              pending = @db[:jobs].where(kind: "workflow.phase_prompt", effect_started_at: nil, status: %w[pending blocked]).all.any? { |job| job[:payload]["workflow_id"] == workflow_id }
              queue_phase(workflow_id, expected_version + 1) if pending
            end
            @reviews.queue_release(workflow_id, expected_version + 1) if action == "resume"
            @sessions.stop(workflow_id: workflow_id) if %w[finish cancel].include?(action)
            @db[:audit].insert(event_key: "workflow:#{workflow_id}:#{expected_version}:#{action}", action: action,
                               details: Sequel.pg_jsonb({ "inbox_id" => inbox_id, "workflow_id" => workflow_id, "version" => expected_version }))
          end
        end
        action
      end

      sig { params(workflow_id: String, gate: String).void }
      def advance_approval(workflow_id:, gate:)
        @lock.call(workflow_id) do
          w = @db[:workflows][id: workflow_id]
          raise ArgumentError, "Approval phase mismatch" unless w[:phase] == "#{gate}_human_approval"

          ref = w[:artifacts][gate]
          approval = ref && @db[:approvals][workflow_id: workflow_id, kind: gate, target_commit: ref["commit"]]
          raise ArgumentError, "Exact human approval missing" unless approval

          record = @db[:reviews].where(workflow_id: workflow_id, gate: gate).order(Sequel.desc(:round)).first
          raise ArgumentError, "Approving review missing" unless record && record[:verdict] == "approve" && record[:target_commit] == ref["commit"]

          @evidence.approval(w, record)
          validate_prior_approvals(w, gate == "plan" ? %w[spec plan] : %w[spec])
          phase = gate == "spec" ? "plan_writing" : "implementation"
          @db.transaction do
            @db[:workflows].where(id: workflow_id, version: w[:version]).update(phase: phase, version: w[:version] + 1)
            queue_phase(workflow_id, w[:version] + 1)
            @reviews.queue_release(workflow_id, w[:version] + 1)
          end
        end
      end

      sig { params(job: Job, store: Domains::Jobs::Store).void }
      def call(job, store)
        payload = job_payload(job)
        job_id = job_string(job, :id)
        lease_token = job_string(job, :lease_token)
        w = @db[:workflows][id: payload.fetch("workflow_id")]
        @lock.call(w[:id]) do
          w = @db[:workflows][id: w[:id]]
          unless @policy.dispatch_allowed?
            store.block(id: job_id, lease_token: lease_token, reason: "Live Writer dispatch evidence required")
            return
          end
          if w[:phase] == "paused"
            store.defer(id: job_id, lease_token: lease_token, reason: "Paused")
            return
          end
          return unless payload["version"] == w[:version]
          raise ArgumentError, "Phase changed" unless %w[spec_writing plan_writing implementation].include?(w[:phase])

          current_writer = @db[:sessions][workflow_id: w[:id], role: "writer", active: true]
          live = current_writer && @herdr.get(current_writer[:pane_id])
          if live && live["agent_status"] == "working" && live["agent_session"] == current_writer[:runtime_identity]
            store.defer(id: job_id, lease_token: lease_token, reason: "Writer busy")
            return
          end
          s = validate_sessions(w, "writer").first
          raise ArgumentError, "Writer session missing" unless s

          d = @source.human(w[:source_inbox_id], destination: w[:channel_id])
          gate = { "plan_writing" => "spec", "implementation" => "plan" }[w[:phase]]
          if gate
            record = @db[:reviews].where(workflow_id: w[:id], gate: gate).order(Sequel.desc(:round)).first
            raise ArgumentError, "Required artifact approval missing" unless record && @db[:approvals][workflow_id: w[:id], kind: gate, target_commit: record[:target_commit]]

            validate_prior_approvals(w, gate == "plan" ? %w[spec plan] : %w[spec])
          end
          raise IOError, "Dispatch lease lost" unless store.begin_effect(id: job_id, lease_token: lease_token)

          latest_review = @db[:reviews].where(workflow_id: w[:id], verdict: "changes_requested").order(Sequel.desc(:id)).first
          feedback = latest_review ? "Read corrective feedback in #{latest_review[:review_path]} at #{latest_review[:review_commit]} for target #{latest_review[:target_commit]}. " : ""
          prompt = feedback + "Work only in #{w[:worktree_path]} on #{w[:branch]}. " \
                              "Current phase: #{w[:phase]}. " \
                              "Human request: #{d.body}\nWrite docs/spec.md then docs/plan.md in their respective phases; implementation requires approved spec and plan. " \
                              "Report exact clean commits via artifact-ready. " \
                              "Stop changes during review. " \
                              "Do not create independent sessions."
          @herdr.prompt(row_string(s, :pane_id), prompt)
        end
      end

      sig { params(id: String, version: Integer).void }
      def queue_phase(id, version)
        Domains::Jobs::Store.new.enqueue(kind: "workflow.phase_prompt", payload: { "workflow_id" => id, "version" => version }, key: "workflow:phase:#{id}:#{version}")
      end

      private

      sig { params(w: Domains::Reviews::GitEvidence::Workflow, gates: T::Array[String]).void }
      def validate_prior_approvals(w, gates)
        gates.each do |gate|
          commit = artifact_commit!(w.fetch(:artifacts), gate)

          approval = @db[:approvals][workflow_id: w[:id], kind: gate, target_commit: commit]
          raise ArgumentError, "Required exact artifact approval missing" unless approval

          @evidence.approved_artifact(w, approval)
        end
      end

      sig { params(value: BasicObject, gate: String).returns(String) }
      def artifact_commit!(value, gate)
        hash = Sequel::Postgres::JSONBHash === value ? value.to_hash : Hash.try_convert(value)
        raise ArgumentError, "Invalid workflow artifacts" unless hash

        ref = hash[gate]
        raise ArgumentError, "Invalid workflow artifact" unless ref.is_a?(Hash)

        commit = ref["commit"]
        raise ArgumentError, "Invalid workflow artifact" unless commit.is_a?(String)

        commit
      end

      sig { params(w: T::Hash[Symbol, Object], role: T.nilable(String)).returns(T::Array[T::Hash[Symbol, Object]]) }
      def validate_sessions(w, role = nil)
        rows = @db[:sessions].where(workflow_id: w[:id], active: true)
        rows = rows.where(role: role) if role
        rows = rows.all
        raise ArgumentError, "Required session missing" if rows.empty?

        rows.each do |s|
          live = @herdr.get(s[:pane_id])
          raise ArgumentError, "Session uncertain or replaced" unless s[:runtime_identity] && live["agent_session"] == s[:runtime_identity] && %w[idle done].include?(live["agent_status"]) && s[:credential_expires_at] > Time.now
        end
        rows
      end

      sig { params(job: Job).returns(T::Hash[String, Object]) }
      def job_payload(job)
        payload = job.fetch(:payload)
        raise ArgumentError, "Invalid workflow job" unless payload.is_a?(Hash) && payload.keys.all? { |key| key.is_a?(String) }

        payload
      end

      sig { params(job: Job, key: Symbol).returns(String) }
      def job_string(job, key)
        value = job.fetch(key)
        raise ArgumentError, "Invalid workflow job" unless value.is_a?(String)

        value
      end

      sig { params(row: T::Hash[Symbol, Object], key: Symbol).returns(String) }
      def row_string(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Invalid workflow row" unless value.is_a?(String)

        value
      end
    end
  end
end
