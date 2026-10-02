# frozen_string_literal: true

module Domains
  module Workflows
    class Coordinator
      def initialize(db, source:, herdr:, evidence:, reviews:, sessions:, policy: Policy.new)
        @db, @source, @herdr, @evidence, @reviews, @sessions, @policy = db, source, herdr, evidence, reviews, sessions, policy
        @lock = Lock.new(db)
      end

      def control(inbox_id:, workflow_id:, action:, expected_version:)
        raise ArgumentError, "Unsupported workflow action" unless %w[pause resume finish cancel].include?(action)

        w = @db[:workflows][id: workflow_id] or raise ArgumentError, "Missing workflow"
        @source.human(inbox_id, destination: w[:channel_id])
        @lock.call(workflow_id) do
          w = @db[:workflows][id: workflow_id]
          raise ArgumentError, "Workflow version changed" unless w[:version] == expected_version && !w[:archived_at]

          changes = case action
                    when "pause"
                      raise ArgumentError, "Cannot pause this phase" if %w[paused closed cancelled blocked].include?(w[:phase])

                      { phase: "paused", saved_phase: w[:phase], paused_commit: @evidence.head(w) }
                    when "resume"
                      raise ArgumentError, "Not paused" unless w[:phase] == "paused" && w[:saved_phase] && w[:saved_phase] != "blocked"

                      live_role = w[:saved_phase].end_with?("_review") ? "reviewer" : "writer"
                      validate_sessions(w, live_role)
                      raise ArgumentError, "Paused revision changed without verified callback" unless @evidence.current(w) == w[:paused_commit]

                      { phase: w[:saved_phase], saved_phase: nil, paused_commit: nil }
                    when "finish"
                      raise ArgumentError, "Only delivered workflow may finish" unless w[:phase] == "done"

                      validate_sessions(w)
                      { phase: "closed" }
                    when "cancel"
                      raise ArgumentError, "Already closed" if %w[closed cancelled].include?(w[:phase])

                      validate_sessions(w)
                      { phase: "cancelled" }
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

      def call(job, store)
        w = @db[:workflows][id: job[:payload].fetch("workflow_id")]
        @lock.call(w[:id]) do
          w = @db[:workflows][id: w[:id]]
          unless @policy.dispatch_allowed?
            store.block(id: job[:id], lease_token: job[:lease_token], reason: "Live Writer dispatch evidence required")
            return
          end
          if w[:phase] == "paused"
            store.defer(id: job[:id], lease_token: job[:lease_token], reason: "Paused")
            return
          end
          return unless job[:payload]["version"] == w[:version]
          raise ArgumentError, "Phase changed" unless %w[spec_writing plan_writing implementation].include?(w[:phase])

          current_writer = @db[:sessions][workflow_id: w[:id], role: "writer", active: true]
          live = current_writer && @herdr.get(current_writer[:pane_id])
          if live && live["agent_status"] == "working" && live["agent_session"] == current_writer[:runtime_identity]
            store.defer(id: job[:id], lease_token: job[:lease_token], reason: "Writer busy")
            return
          end
          s = validate_sessions(w, "writer").first
          d = @source.human(w[:source_inbox_id], destination: w[:channel_id])
          gate = { "plan_writing" => "spec", "implementation" => "plan" }[w[:phase]]
          if gate
            record = @db[:reviews].where(workflow_id: w[:id], gate: gate).order(Sequel.desc(:round)).first
            raise ArgumentError, "Required artifact approval missing" unless record && @db[:approvals][workflow_id: w[:id], kind: gate, target_commit: record[:target_commit]]

            validate_prior_approvals(w, gate == "plan" ? %w[spec plan] : %w[spec])
          end
          raise IOError, "Dispatch lease lost" unless store.begin_effect(id: job[:id], lease_token: job[:lease_token])

          latest_review = @db[:reviews].where(workflow_id: w[:id], verdict: "changes_requested").order(Sequel.desc(:id)).first
          feedback = latest_review ? "Read corrective feedback in #{latest_review[:review_path]} at #{latest_review[:review_commit]} for target #{latest_review[:target_commit]}. " : ""
          prompt = feedback + "Work only in #{w[:worktree_path]} on #{w[:branch]}. " \
                              "Current phase: #{w[:phase]}. " \
                              "Human request: #{d.body}\nWrite docs/spec.md then docs/plan.md in their respective phases; implementation requires approved spec and plan. " \
                              "Report exact clean commits via artifact-ready. " \
                              "Stop changes during review. " \
                              "Do not create independent sessions."
          @herdr.prompt(s[:pane_id], prompt)
        end
      end

      def queue_phase(id, version)
        Domains::Jobs::Store.new(@db).enqueue(kind: "workflow.phase_prompt", payload: { "workflow_id" => id, "version" => version }, key: "workflow:phase:#{id}:#{version}")
      end
      private def validate_prior_approvals(w, gates)
        gates.each do |gate|
          ref = w[:artifacts][gate]
          approval = ref && @db[:approvals][workflow_id: w[:id], kind: gate, target_commit: ref["commit"]]
          raise ArgumentError, "Required exact artifact approval missing" unless approval

          @evidence.approved_artifact(w, approval)
        end
      end

      private def validate_sessions(w, role = nil)
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
    end
  end
end
