# frozen_string_literal: true

require "digest"
module Domains
  module Reviews
    class Coordinator
      PHASES = { "spec" => "spec_writing", "plan" => "plan_writing", "implementation" => "implementation" }.freeze
      def initialize(db, herdr:, evidence:, routing:, policy: Domains::Workflows::Policy.new)
        @db, @herdr, @evidence, @routing, @policy = db, herdr, evidence, routing, policy
        @lock = Domains::Workflows::Lock.new(db)
      end

      def ready(token:, generation:, kind:, commit:)
        raise ArgumentError, "Artifact kind/commit required" unless PHASES.key?(kind) && commit.match?(/\A[0-9a-f]{40}\z/)

        ready_session(session_id: session(token, generation, "writer")[:id], generation: generation, kind: kind, commit: commit)
      end

      def ready_session(session_id:, generation:, kind:, commit:)
        raise ArgumentError, "Artifact kind/commit required" unless PHASES.key?(kind) && commit.match?(/\A[0-9a-f]{40}\z/)

        s = checked_session(session_id, generation, "writer")
        @lock.call(s[:workflow_id]) do
          w = @db[:workflows][id: s[:workflow_id]]
          old = @db[:reviews][workflow_id: w[:id], gate: kind, target_commit: commit]
          return old[:id] if old

          current_phase = w[:phase] == "paused" ? w[:saved_phase] : w[:phase]
          raise ArgumentError, "Writer phase required" unless current_phase == PHASES[kind] && !w[:archived_at]

          settled!(s)
          path = kind == "implementation" ? nil : "docs/#{kind}.md"
          @evidence.artifact(w, commit, path)
          round = (@db[:reviews].where(workflow_id: w[:id], gate: kind).max(:round) || 0) + 1
          raise ArgumentError, "Review rounds exhausted" if round > 3

          base = kind == "implementation" ? @evidence.base(w, commit) : nil
          reviewer = @db[:sessions][workflow_id: w[:id], role: "reviewer", active: true]
          raise ArgumentError, "Reviewer missing/diversity violated" unless reviewer && reviewer[:configuration]["provider"] != s[:configuration]["provider"] && reviewer[:configuration]["family"] != s[:configuration]["family"]

          @db.transaction do
            id = @db[:reviews].insert(workflow_id: w[:id], gate: kind, round: round, target_commit: commit, base_commit: base,
                                      review_path: "docs/review.md", reviewer_configuration: reviewer[:configuration])
            refs = w[:artifacts].to_h.merge(kind => { "commit" => commit, "path" => path })
            changes = w[:phase] == "paused" ? { saved_phase: "#{kind}_review", paused_commit: commit } : { phase: "#{kind}_review" }
            @db[:workflows].where(id: w[:id], version: w[:version]).update(**changes, artifacts: Sequel.pg_jsonb(refs), version: w[:version] + 1)
            Domains::Jobs::Store.new(@db).enqueue(kind: "review.prompt", payload: { "review_id" => id }, key: "review:#{id}")
            id
          end
        end
      end

      def finish(token:, generation:, review_commit:, verdict:)
        raise ArgumentError, "Exact review result required" unless %w[approve changes_requested].include?(verdict) && review_commit.match?(/\A[0-9a-f]{40}\z/)

        finish_session(session_id: session(token, generation, "reviewer")[:id], generation: generation, review_commit: review_commit, verdict: verdict)
      end

      def finish_session(session_id:, generation:, review_commit:, verdict:)
        raise ArgumentError, "Exact review result required" unless %w[approve changes_requested].include?(verdict) && review_commit.match?(/\A[0-9a-f]{40}\z/)

        s = checked_session(session_id, generation, "reviewer")
        workflow_id = s[:workflow_id]
        old = @db[:reviews][workflow_id: workflow_id, review_commit: review_commit, verdict: verdict]
        return old[:id] if old

        @lock.call(workflow_id) do
          w = @db[:workflows][id: workflow_id]
          current_phase = w[:phase] == "paused" ? w[:saved_phase] : w[:phase]
          kind = current_phase.to_s.delete_suffix("_review")
          raise ArgumentError, "Review lock required" unless PHASES.key?(kind) && current_phase.end_with?("_review")

          record = @db[:reviews].where(workflow_id: workflow_id, gate: kind).order(Sequel.desc(:round)).first
          raise ArgumentError, "Undispatched review" unless record && %w[delivered sending uncertain].include?(record[:dispatch_state]) && !record[:verdict]
          raise ArgumentError, "Reviewer configuration changed" unless s[:configuration] == record[:reviewer_configuration]

          if record[:dispatch_state] != "delivered"
            job = @db[:jobs][dispatch_key: "review:#{record[:id]}"]
            raise ArgumentError, "Review prompt effect unproved" unless job && job[:effect_started_at]
            raise ArgumentError, "Review prompt lease still live" if job[:status] == "running" && job[:lease_expires_at] && job[:lease_expires_at] > Time.now
          end
          settled!(s)
          @evidence.review(w, record, review_commit, verdict, s[:configuration])
          phase = if verdict == "approve"
                    kind == "implementation" ? "pr_ready" : "#{kind}_human_approval"
                  elsif record[:round] >= 3
                    "blocked"
                  else
                    PHASES.fetch(kind)
                  end
          @db.transaction do
            @db[:reviews].where(id: record[:id]).update(review_commit: review_commit, verdict: verdict, dispatch_state: "delivered")
            @db[:jobs].where(dispatch_key: "review:#{record[:id]}").update(status: "complete", lease_token: nil, lease_expires_at: nil)
            if record[:dispatch_state] != "delivered"
              @db[:audit].insert(event_key: "review:receipt:#{record[:id]}", action: "verified_review_prompt_reconciliation",
                                 details: Sequel.pg_jsonb({ "review_id" => record[:id], "target_commit" => record[:target_commit], "review_commit" => review_commit, "session_id" => s[:id], "generation" => generation }))
            end
            changes = w[:phase] == "paused" ? { saved_phase: phase, paused_commit: review_commit } : { phase: phase }
            @db[:workflows].where(id: workflow_id, version: w[:version]).update(**changes, version: w[:version] + 1,
                                                                                           blocker: phase == "blocked" ? "Three review rounds requested changes" : nil)
            queue_release(workflow_id, w[:version] + 1)
            if verdict == "changes_requested" && phase != "blocked"
              Domains::Jobs::Store.new(@db).enqueue(kind: "workflow.phase_prompt", payload: { "workflow_id" => workflow_id, "version" => w[:version] + 1 }, key: "workflow:phase:#{workflow_id}:#{w[:version] + 1}")
            end
            Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: w[:channel_id], thread_id: w[:thread_id], bot: "worker", role: "reviewer",
                                                         body: "Review #{verdict} for #{record[:target_commit]}; committed at #{review_commit}.", key: "review:result:#{record[:id]}")
          end
        end
        workflow_id
      end

      def queue_release(workflow_id, version)
        Domains::Jobs::Store.new(@db).enqueue(kind: "review.release", payload: { "workflow_id" => workflow_id }, key: "review:release:#{workflow_id}:#{version}")
      end

      def release_job(job, _store)
        release(job[:payload].fetch("workflow_id"))
      end

      def release(workflow_id)
        w = @db[:workflows][id: workflow_id]
        return unless PHASES.value?(w[:phase])

        transient = nil
        @db[:queued_messages].where(workflow_id: workflow_id).order(:id).each do |row|
          begin
            result = @routing.route(inbox_id: row[:inbox_id])
            @db[:queued_messages].where(id: row[:id]).delete if result[:id]
          rescue ArgumentError, Domains::Mattermost::Client::Error => error
            if error.is_a?(Domains::Mattermost::Client::Error) && ![403, 404].include?(error.status)
              transient = error
              break
            end
            # Retain invalid sources for reconciliation; one revoked message
            # must not prevent other verified instructions from being released.
            @db[:audit].insert_conflict(target: :event_key).insert(event_key: "release:invalid:#{row[:id]}", action: "release_source_rejected", details: Sequel.pg_jsonb({ "workflow_id" => workflow_id, "inbox_id" => row[:inbox_id] }))
          end
        end
        @db[:followups].where(workflow_id: workflow_id, status: "queued").each do |row|
          @db[:jobs].where(dispatch_key: "followup:#{row[:id]}", status: "blocked", effect_started_at: nil).update(status: "pending", attempts: 0, available_at: Time.now, last_error: nil)
        end
        raise transient if transient
      end

      def call(job, store)
        record = @db[:reviews][id: job[:payload].fetch("review_id")]
        @lock.call(record[:workflow_id]) do
          return if record[:dispatch_state] == "delivered"
          raise ArgumentError, "Uncertain review prompt" unless record[:dispatch_state] == "queued"

          unless @policy.dispatch_allowed?
            store.block(id: job[:id], lease_token: job[:lease_token], reason: "Live review dispatch evidence required")
            return
          end
          w = @db[:workflows][id: record[:workflow_id]]
          if w[:phase] == "paused"
            store.defer(id: job[:id], lease_token: job[:lease_token], reason: "Paused review")
            return
          end
          raise ArgumentError, "Review phase changed" unless w[:phase] == "#{record[:gate]}_review"

          @evidence.artifact(w, record[:target_commit], w[:artifacts].fetch(record[:gate])["path"])
          s = @db[:sessions][workflow_id: w[:id], role: "reviewer", active: true]
          raise ArgumentError, "Reviewer configuration changed" unless s && s[:configuration] == record[:reviewer_configuration]

          live = @herdr.get(s[:pane_id])
          if live["agent_status"] == "working" && live["agent_session"] == s[:runtime_identity]
            store.defer(id: job[:id], lease_token: job[:lease_token], reason: "Reviewer busy")
            return
          end
          settled!(s)
          @db[:reviews].where(id: record[:id]).update(dispatch_state: "sending")
          begin
            raise IOError, "Dispatch lease lost" unless store.begin_effect(id: job[:id], lease_token: job[:lease_token])

            prompt = "Review #{record[:gate]} target #{record[:target_commit]}, base #{record[:base_commit]}. " \
                     "Change only #{record[:review_path]}; append Target, Provider, Model, Family, Verdict and Reviewed-at (UTC ISO8601) fields. " \
                     "Report the exact review commit via review-ready. Do not change the artifact or start sessions."
            @herdr.prompt(s[:pane_id], prompt)
            @db[:reviews].where(id: record[:id]).update(dispatch_state: "delivered")
          rescue StandardError
            @db[:reviews].where(id: record[:id]).update(dispatch_state: "uncertain")
            raise
          end
        end
      end
      private def session(token, generation, role)
        s = @db[:sessions][credential_digest: Digest::SHA256.hexdigest(token), generation: generation, active: true, role: role]
        latest = s && @db[:sessions].where(workflow_id: s[:workflow_id], role: role).max(:generation)
        raise ArgumentError, "Invalid callback session" unless s && s[:credential_expires_at] > Time.now && latest == generation

        s
      end
      private def checked_session(id, generation, role)
        s = @db[:sessions][id: id, generation: generation, active: true, role: role]
        latest = s && @db[:sessions].where(workflow_id: s[:workflow_id], role: role).max(:generation)
        raise ArgumentError, "Stale callback session" unless s && latest == generation && s[:credential_expires_at] > Time.now

        s
      end
      private def settled!(s)
        live = @herdr.get(s[:pane_id])
        raise ArgumentError, "Session not settled or replaced" unless s[:runtime_identity] && live["agent_session"] == s[:runtime_identity] && %w[idle done].include?(live["agent_status"])
      end
    end
  end
end
