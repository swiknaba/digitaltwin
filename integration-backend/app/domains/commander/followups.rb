# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    class Followups
      extend T::Sig

      Status = Adapters::Herdr::Dto::AgentStatus
      SETTLED = T.let([Status::Idle, Status::Done].freeze, T::Array[Adapters::Herdr::Dto::AgentStatus])

      sig do
        params(db: Sequel::Database, herdr: Adapters::Herdr::Client, resolver: Domains::Messaging::DeliveryVerifier,
               membership: T.proc.params(channel_id: String, user_id: String).returns(T::Boolean),
               policy: Domains::Workflows::Policy, handle: String).void
      end
      def initialize(db, herdr:, resolver:, membership:, policy: Domains::Workflows::Policy.new, handle: ENV.fetch("AGENT_HANDLE", "agent"))
        @db = db
        @herdr = herdr
        @resolver = resolver
        @membership = membership
        @policy = policy
        @handle = handle
        @inbox = T.let(Domains::Messaging::Inbox.new, Domains::Messaging::Inbox)
        @catalog = T.let(Domains::Workflows::Catalog.new, Domains::Workflows::Catalog)
      end

      # All future review/session transitions must use this same workflow mutex.
      # Keep the connection checked out across commits, never network in a DB tx.
      sig { params(id: String, before_effect: T.proc.returns(T::Boolean)).returns(String) }
      def deliver(id, before_effect: -> { true })
        row = @db[:followups][id: id] or raise ArgumentError, "Missing instruction"
        @db.synchronize do
          lock = @db.get(Sequel.function(:pg_try_advisory_lock, Sequel.function(:hashtextextended, row[:workflow_id], 0)))
          return "queued" unless lock

          begin
            row = @db[:followups][id: id]
            return row[:status] unless row[:status] == "queued"
            return "queued" unless @policy.dispatch_allowed?

            w = T.must(@catalog.find(id: row[:workflow_id]))
            phase = w.phase
            return "queued" if phase == Domains::Workflows::Dto::Phase::Paused || phase.review? || phase.human_approval?
            return block(id, "Workflow inactive") if w.archived_at || phase.terminal? || phase == Domains::Workflows::Dto::Phase::Blocked

            return "queued" unless phase.writing?

            source = T.must(@inbox.find(id: row[:inbox_id]))
            d = @resolver.delivery(post_id: source.post_id, channel_id: source.channel_id, event_kind: Domains::Messaging::Dto::EventKind::Posted)
            valid_source = d.actor.member && !d.actor.bot && d.actor.user_id == source.user_id && d.post_revision == source.post_revision
            valid_source &&= d.body == source.verified_delivery.body && @membership.call(w.channel_id, d.actor.user_id)
            return block(id, "Source or membership changed") unless valid_source

            session = @db[:sessions][id: row[:session_id], generation: row[:generation], workflow_id: w.id, role: "writer"]
            latest = session && @db[:sessions].where(workflow_id: w.id, role: "writer").max(:generation)
            return block(id, "Session stale; reconcile without creating a session") unless session && latest == row[:generation]

            unless session[:active]
              pending_start = @db[:session_operations][session_id: session[:id], kind: "start", state: %w[queued sending uncertain]]
              return pending_start ? "queued" : block(id, "Inactive session requires reconciliation")
            end
            if session[:credential_expires_at] <= Time.now
              renewal = Platform::Jobs::Store.new.find(id: Domains::Sessions::Lifecycle.schedule_renewal(@db, session))
              live_renewal = [Platform::Jobs::Dto::JobStatus::Pending, Platform::Jobs::Dto::JobStatus::Running].include?(renewal&.status)
              return live_renewal ? "queued" : block(id, "Credential renewal requires reconciliation")
            end

            pending = @db[:followups].where(workflow_id: w.id).where(earlier_than(id)).where(status: %w[queued sending uncertain]).count
            return "queued" unless pending.zero?

            live = @herdr.pane(session[:pane_id])
            same_conversation = session[:runtime_identity] && live.agent_session&.serialize == session[:runtime_identity]
            return "queued" if live.agent_status == Status::Working && same_conversation

            ready = SETTLED.include?(live.agent_status) && live.interactive_ready == true && live.launch_pending == false
            identity = same_conversation && live.name == session[:alias] && live.cwd == w.worktree_path && live.agent == session[:configuration]["cli"]
            return block(id, "Session not ready") unless ready && identity

            @db[:followups].where(id: id, status: "queued").update(status: "sending")
            begin
              raise IOError, "Dispatch lease lost" unless before_effect.call

              @herdr.prompt(pane_id: session[:pane_id], text: source.verified_delivery.body.sub(/\A@#{Regexp.escape(@handle)} route [a-zA-Z0-9_-]+\n/, ""))
              @db[:followups].where(id: id).update(status: "delivered", delivered_at: Time.now)
              "delivered"
            rescue StandardError
              @db.transaction do
                @db[:followups].where(id: id).update(status: "uncertain", reason: "Socket effect requires reconciliation; do not resend")
                message = Domains::Messaging::Dto::OutgoingMessage.new(
                  channel_id: source.channel_id,
                  thread_id: source.thread_id,
                  bot: Domains::Messaging::Dto::Bot::Agent,
                  role: Domains::Messaging::Dto::SpeakerRole::Controller,
                  body: "Instruction #{id} has an uncertain send result. Inspect this conversation, then use @#{@handle} recover-followup #{id} delivered|discard. No automatic resend.",
                  key: "followup:uncertain:#{id}"
                )
                Platform::Unwrap.call(Domains::Messaging::Outbox.new.enqueue(message: message))
              end
              "uncertain"
            end
          ensure
            @db.get(Sequel.function(:pg_advisory_unlock, Sequel.function(:hashtextextended, row[:workflow_id], 0)))
          end
        end
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        state = deliver(followup_id(job), before_effect: -> { job.lease.begin_effect })
        if state == "queued" && @policy.dispatch_allowed?
          Platform::Jobs::Dto::Decision.defer("Waiting for workflow/session readiness")
        elsif state != "delivered"
          Platform::Jobs::Dto::Decision.block("Follow-up #{state}; reconciliation or gated release required")
        else
          Platform::Jobs::Dto::Decision.complete
        end
      end

      sig { params(id: String, inbox_id: String, outcome: String).returns(String) }
      def reconcile(id:, inbox_id:, outcome:)
        raise ArgumentError, "Explicit outcome required" unless %w[delivered discard].include?(outcome)

        row = @db[:followups][id: id] or raise ArgumentError, "Missing instruction"
        source = @inbox.find(id: inbox_id) or raise ArgumentError, "Missing recovery source"
        original = T.must(@inbox.find(id: row[:inbox_id]))
        d = @resolver.delivery(post_id: source.post_id, channel_id: source.channel_id, event_kind: Domains::Messaging::Dto::EventKind::Posted)
        command = "@#{@handle} recover-followup #{id} #{outcome}"
        authority = d.actor.member && !d.actor.bot && d.actor.user_id == original.user_id && d.actor.user_id == source.user_id
        authority &&= d.post_revision == source.post_revision && d.body == command && source.verified_delivery.body == command
        raise ArgumentError, "Recovery requires the original human's exact instruction binding" unless authority

        w = T.must(@catalog.find(id: row[:workflow_id]))
        raise ArgumentError, "Recovery destination membership required" unless @membership.call(w.channel_id, d.actor.user_id)

        audit = Platform::Audit::Log.new
        jobs = Platform::Jobs::Store.new
        Platform::Lock.new.call(key: w.id) do
          row = @db[:followups][id: id]
          receipt_key = "followup:recovery:#{id}"
          receipt = audit.find(event_key: receipt_key)
          if receipt
            old = Dto::FollowupRecoveryAudit.from_hash(receipt.details, true)
            raise ArgumentError, "Recovery outcome already bound" unless old.outcome == outcome && old.user_id == d.actor.user_id

            return outcome
          end
          raise ArgumentError, "Instruction does not require uncertain-send recovery" unless row[:status] == "uncertain" || row[:status] == "sending"

          job = jobs.find_by_key(dispatch_key: "followup:#{id}")
          lease_expires_at = job&.lease_expires_at
          raise ArgumentError, "Send still holds a live lease" if job&.status == Platform::Jobs::Dto::JobStatus::Running && lease_expires_at && lease_expires_at > Time.now

          s = @db[:sessions][id: row[:session_id], workflow_id: w.id, generation: row[:generation], role: "writer", active: true]
          latest = @db[:sessions].where(workflow_id: w.id, role: "writer").max(:generation)
          live = s && @herdr.pane(s[:pane_id])
          settled = live && latest == row[:generation] && s[:runtime_identity] && live.agent_session&.serialize == s[:runtime_identity]
          settled &&= SETTLED.include?(live.agent_status) && live.name == s[:alias]
          settled &&= live.cwd == w.worktree_path && live.agent == s[:configuration]["cli"]
          raise ArgumentError, "Same conversation must be positively settled" unless settled

          @db.transaction do
            details = Dto::FollowupRecoveryAudit.new(inbox_id: inbox_id, followup_id: id, workflow_id: w.id, session_id: s[:id], generation: s[:generation], user_id: d.actor.user_id, outcome: outcome)
            audit.record(event_key: receipt_key, action: "human_followup_reconciliation", details: details)
            @db[:followups].where(id: id).update(status: outcome == "delivered" ? "delivered" : "blocked", reason: "Human #{outcome} confirmation at inbox #{inbox_id}; no resend", delivered_at: outcome == "delivered" ? Time.now : nil)
            jobs.close_reconciled(id: job.id) if job
            message = Domains::Messaging::Dto::OutgoingMessage.new(
              channel_id: d.channel_id,
              thread_id: d.thread_id,
              bot: Domains::Messaging::Dto::Bot::Agent,
              role: Domains::Messaging::Dto::SpeakerRole::Controller,
              body: "Instruction #{id}: human confirmed #{outcome}; no prompt was resent.",
              key: receipt_key
            )
            Platform::Unwrap.call(Domains::Messaging::Outbox.new.enqueue(message: message))
          end
          outcome
        end
      end

      # Ids are random, so delivery order follows created_at with id as tiebreaker.
      sig { params(id: String).returns(Sequel::SQL::Expression) }
      private def earlier_than(id)
        created_at = @db[:followups].where(id: id).select(:created_at)
        Sequel.|(Sequel[:followups][:created_at] < created_at,
                 Sequel.&(Sequel[:followups][:created_at] =~ created_at, Sequel[:followups][:id] < id))
      end

      sig { params(id: String, reason: String).returns(String) }
      private def block(id, reason)
        @db[:followups].where(id: id).update(status: "blocked", reason: reason)
        "blocked"
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(String) }
      private def followup_id(job)
        value = Dto::FollowupJob.from_hash(job.payload, true).followup_id
        raise ArgumentError, "Follow-up job is malformed" if value.empty?

        value
      end
    end
  end
end
