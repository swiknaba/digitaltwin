# typed: strict
# frozen_string_literal: true

module Domains
  module Controller
    class Followups
      extend T::Sig
      sig do
        params(db: Sequel::Database, herdr: Domains::Sessions::Herdr, resolver: Source::DeliveryResolver,
               membership: T.proc.params(channel_id: String, user_id: String).returns(T::Boolean),
               policy: Domains::Workflows::Policy, handle: String).void
      end
      def initialize(db, herdr:, resolver:, membership:, policy: Domains::Workflows::Policy.new, handle: ENV.fetch("AGENT_HANDLE", "agent"))
        @db = T.let(db, Sequel::Database)
        @herdr = T.let(herdr, Domains::Sessions::Herdr)
        @resolver = T.let(resolver, Source::DeliveryResolver)
        @membership = T.let(membership, T.proc.params(channel_id: String, user_id: String).returns(T::Boolean))
        @policy = T.let(policy, Domains::Workflows::Policy)
        @handle = T.let(handle, String)
      end

      # All future review/session transitions must use this same workflow mutex.
      # Keep the connection checked out across commits, never network in a DB tx.
      sig { params(id: Integer, before_effect: T.proc.returns(T::Boolean)).returns(String) }
      def deliver(id, before_effect: -> { true })
        row = @db[:followups][id: id] or raise ArgumentError, "Missing instruction"
        @db.synchronize do
          lock = @db.get(Sequel.function(:pg_try_advisory_lock, Sequel.function(:hashtextextended, row[:workflow_id], 0)))
          return "queued" unless lock

          begin
            row = @db[:followups][id: id]
            return row[:status] unless row[:status] == "queued"
            return "queued" unless @policy.dispatch_allowed?

            w = @db[:workflows][id: row[:workflow_id]]
            return "queued" if w[:phase] == "paused" || w[:phase].end_with?("_review") || w[:phase].end_with?("_human_approval")
            return block(id, "Workflow inactive") if w[:archived_at] || Routing::TERMINAL.include?(w[:phase]) || w[:phase] == "blocked"

            return "queued" unless %w[spec_writing plan_writing implementation].include?(w[:phase])

            source = @db[:inbox][id: row[:inbox_id]]
            d = @resolver.delivery(post_id: source[:post_id], channel_id: source[:channel_id], event_kind: "posted")
            valid_source = d.actor.member && !d.actor.bot && d.actor.user_id == source[:user_id] && d.post_revision == source[:post_revision]
            valid_source &&= d.body == source[:verified_delivery].fetch("body") && @membership.call(w[:channel_id], d.actor.user_id)
            return block(id, "Source or membership changed") unless valid_source

            session = @db[:sessions][id: row[:session_id], generation: row[:generation], workflow_id: w[:id], role: "writer"]
            latest = session && @db[:sessions].where(workflow_id: w[:id], role: "writer").max(:generation)
            return block(id, "Session stale; reconcile without creating a session") unless session && latest == row[:generation]

            unless session[:active]
              pending_start = @db[:session_operations][session_id: session[:id], kind: "start", state: %w[queued sending uncertain]]
              return pending_start ? "queued" : block(id, "Inactive session requires reconciliation")
            end
            if session[:credential_expires_at] <= Time.now
              renewal = Domains::Sessions::Lifecycle.schedule_renewal(@db, session)
              state = @db[:jobs][id: renewal][:status]
              return %w[pending running].include?(state) ? "queued" : block(id, "Credential renewal requires reconciliation")
            end

            pending = @db[:followups].where(workflow_id: w[:id]).where(Sequel[:followups][:id] < id).where(status: %w[queued sending uncertain]).count
            return "queued" unless pending.zero?

            live = @herdr.get(session[:pane_id])
            return "queued" if live["agent_status"] == "working" && session[:runtime_identity] && live["agent_session"] == session[:runtime_identity]

            ready = %w[idle done].include?(live["agent_status"]) && live["interactive_ready"] == true && live["launch_pending"] == false
            identity = session[:runtime_identity] && live["agent_session"] == session[:runtime_identity] && live["name"] == session[:alias] && live["cwd"] == w[:worktree_path] && live["agent"] == session[:configuration]["cli"]
            return block(id, "Session not ready") unless ready && identity

            @db[:followups].where(id: id, status: "queued").update(status: "sending")
            begin
              raise IOError, "Dispatch lease lost" unless before_effect.call

              @herdr.prompt(session[:pane_id], source[:verified_delivery].fetch("body").sub(/\A@#{Regexp.escape(@handle)} route [a-zA-Z0-9-]+\n/, ""))
              @db[:followups].where(id: id).update(status: "delivered", delivered_at: Time.now)
              "delivered"
            rescue StandardError
              @db.transaction do
                @db[:followups].where(id: id).update(status: "uncertain", reason: "Socket effect requires reconciliation; do not resend")
                Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: source[:channel_id], thread_id: source[:thread_id], bot: "agent", role: "controller",
                                                             body: "Instruction #{id} has an uncertain send result. Inspect this conversation, then use @#{@handle} recover-followup #{id} delivered|discard. No automatic resend.",
                                                             key: "followup:uncertain:#{id}")
              end
              "uncertain"
            end
          ensure
            @db.get(Sequel.function(:pg_advisory_unlock, Sequel.function(:hashtextextended, row[:workflow_id], 0)))
          end
        end
      end

      sig { params(job: Domains::Jobs::Store::Job, store: Domains::Jobs::Store).void }
      def call(job, store)
        lease_token = job.lease_token
        raise ArgumentError, "Follow-up job has no lease" unless lease_token

        state = deliver(followup_id(job), before_effect: -> { store.begin_effect(id: job.id, lease_token: lease_token) })
        if state == "queued" && @policy.dispatch_allowed?
          store.defer(id: job.id, lease_token: lease_token, reason: "Waiting for workflow/session readiness")
        elsif state != "delivered"
          store.block(id: job.id, lease_token: lease_token, reason: "Follow-up #{state}; reconciliation or gated release required")
        end
      end

      sig { params(id: Integer, inbox_id: T.any(Integer, String), outcome: String).returns(String) }
      def reconcile(id:, inbox_id:, outcome:)
        raise ArgumentError, "Explicit outcome required" unless %w[delivered discard].include?(outcome)

        row = @db[:followups][id: id] or raise ArgumentError, "Missing instruction"
        source = @db[:inbox][id: inbox_id] or raise ArgumentError, "Missing recovery source"
        original = @db[:inbox][id: row[:inbox_id]]
        d = @resolver.delivery(post_id: source[:post_id], channel_id: source[:channel_id], event_kind: "posted")
        command = "@#{@handle} recover-followup #{id} #{outcome}"
        authority = d.actor.member && !d.actor.bot && d.actor.user_id == original[:user_id] && d.actor.user_id == source[:user_id]
        authority &&= d.post_revision == source[:post_revision] && d.body == command && source[:verified_delivery]["body"] == command
        raise ArgumentError, "Recovery requires the original human's exact instruction binding" unless authority

        w = @db[:workflows][id: row[:workflow_id]]
        raise ArgumentError, "Recovery destination membership required" unless @membership.call(w[:channel_id], d.actor.user_id)

        Domains::Workflows::Lock.new(@db).call(w[:id]) do
          row = @db[:followups][id: id]
          receipt_key = "followup:recovery:#{id}"
          old = @db[:audit][event_key: receipt_key]
          if old
            raise ArgumentError, "Recovery outcome already bound" unless old[:details]["outcome"] == outcome && old[:details]["user_id"] == d.actor.user_id

            return outcome
          end
          raise ArgumentError, "Instruction does not require uncertain-send recovery" unless row[:status] == "uncertain" || row[:status] == "sending"

          job = @db[:jobs][dispatch_key: "followup:#{id}"]
          raise ArgumentError, "Send still holds a live lease" if job && job[:status] == "running" && job[:lease_expires_at] && job[:lease_expires_at] > Time.now

          s = @db[:sessions][id: row[:session_id], workflow_id: w[:id], generation: row[:generation], role: "writer", active: true]
          latest = @db[:sessions].where(workflow_id: w[:id], role: "writer").max(:generation)
          live = s && @herdr.get(s[:pane_id])
          settled = s && latest == row[:generation] && s[:runtime_identity] && live["agent_session"] == s[:runtime_identity]
          settled &&= %w[idle done].include?(live["agent_status"]) && live["name"] == s[:alias]
          settled &&= live["cwd"] == w[:worktree_path] && live["agent"] == s[:configuration]["cli"]
          raise ArgumentError, "Same conversation must be positively settled" unless settled

          @db.transaction do
            details = { "inbox_id" => inbox_id, "followup_id" => id, "workflow_id" => w[:id], "session_id" => s[:id], "generation" => s[:generation], "user_id" => d.actor.user_id, "outcome" => outcome }
            @db[:audit].insert(event_key: receipt_key, action: "human_followup_reconciliation", details: Sequel.pg_jsonb(details))
            @db[:followups].where(id: id).update(status: outcome == "delivered" ? "delivered" : "blocked", reason: "Human #{outcome} confirmation at inbox #{inbox_id}; no resend", delivered_at: outcome == "delivered" ? Time.now : nil)
            @db[:jobs].where(dispatch_key: "followup:#{id}").update(status: "complete", lease_token: nil, lease_expires_at: nil)
            Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: d.channel_id, thread_id: d.thread_id, bot: "agent", role: "controller", body: "Instruction #{id}: human confirmed #{outcome}; no prompt was resent.", key: receipt_key)
          end
          outcome
        end
      end

      sig { params(id: Integer, reason: String).returns(String) }
      private def block(id, reason)
        @db[:followups].where(id: id).update(status: "blocked", reason: reason)
        "blocked"
      end

      sig { params(job: Domains::Jobs::Store::Job).returns(Integer) }
      private def followup_id(job)
        value = job.payload.fetch("followup_id") { raise ArgumentError, "Follow-up job is malformed" }
        raise ArgumentError, "Follow-up job is malformed" unless value.is_a?(Integer) && value.positive?

        value
      end
    end
  end
end
