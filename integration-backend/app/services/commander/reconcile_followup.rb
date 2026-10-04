# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    # Settles a sending or uncertain follow-up on the exact recover-followup
    # command of its original human, once no send holds a live lease and the
    # same Writer conversation is positively settled. Nothing is resent. The
    # audit receipt makes a replay with the same outcome return it again.
    class ReconcileFollowup
      extend T::Sig

      Code = Dto::ErrorCode
      Status = Domains::Commander::Dto::FollowupStatus
      Outcome = ::Services::Commands::Dto::FollowupOutcome
      Messaging = Domains::Messaging
      Identity = Adapters::Herdr::ConversationIdentity
      Writer = Domains::Sessions::Dto::SessionRole::Writer
      Result = T.type_alias { Kirei::Services::Result[Outcome] }

      sig do
        params(herdr: Adapters::Herdr::Client, resolver: Messaging::DeliveryVerifier, membership: Messaging::MembershipCheck, handle: String,
               followups: Domains::Commander::Followups, inbox: Messaging::Inbox, outbox: Messaging::Outbox, catalog: Domains::Workflows::Catalog,
               registry: Domains::Sessions::Registry, audit: Platform::Audit::Log, jobs: Platform::Jobs::Store, lock: Platform::Lock,
               transaction: Platform::Transaction).void
      end
      def initialize(herdr:, resolver:, membership:, handle:, followups: Domains::Commander::Followups.new,
                     inbox: Messaging::Inbox.new, outbox: Messaging::Outbox.new, catalog: Domains::Workflows::Catalog.new,
                     registry: Domains::Sessions::Registry.new, audit: Platform::Audit::Log.new, jobs: Platform::Jobs::Store.new, lock: Platform::Lock.new,
                     transaction: Platform::Transaction.new)
        @herdr = herdr
        @resolver = resolver
        @membership = membership
        @handle = handle
        @followups = followups
        @inbox = inbox
        @outbox = outbox
        @catalog = catalog
        @registry = registry
        @audit = audit
        @jobs = jobs
        @lock = lock
        @transaction = transaction
      end

      sig { params(id: String, inbox_id: String, outcome: Outcome).returns(Result) }
      def call(id:, inbox_id:, outcome:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          row = @followups.find(id: id)
          next failure(Code::MissingFollowup, "Missing instruction") unless row

          source = @inbox.find(id: inbox_id)
          next failure(Code::MissingSource, "Missing recovery source") unless source

          original = T.must(@inbox.find(id: row.inbox_id))
          d = @resolver.delivery(post_id: source.post_id, channel_id: source.channel_id, event_kind: Messaging::Dto::EventKind::Posted)
          command = "@#{@handle} recover-followup #{id} #{outcome.serialize}"
          authority = d.actor.member && !d.actor.bot && d.actor.user_id == original.user_id && d.actor.user_id == source.user_id
          authority &&= d.post_revision == source.post_revision && d.body == command && source.verified_delivery.body == command
          next failure(Code::RecoveryRejected, "Recovery requires the original human's exact instruction binding") unless authority

          w = T.must(@catalog.find(id: row.workflow_id))
          unless @membership.member?(channel_id: w.channel_id, user_id: d.actor.user_id)
            next failure(Code::MembershipRequired, "Recovery destination membership required")
          end

          @lock.call(key: w.id) { reconcile(id, inbox_id, outcome, d, w) }
        rescue Platform::Lock::Busy => error
          failure(Code::Busy, error.message)
        end
      end

      sig do
        params(id: String, inbox_id: String, outcome: Outcome, d: Messaging::Dto::VerifiedDelivery, w: Domains::Workflows::Dto::WorkflowView).returns(Result)
      end
      private def reconcile(id, inbox_id, outcome, d, w)
        row = T.must(@followups.find(id: id))
        receipt_key = "followup:recovery:#{id}"
        receipt = @audit.find(event_key: receipt_key)
        if receipt
          old = Domains::Commander::Dto::FollowupRecoveryAudit.from_hash(receipt.details, true)
          return failure(Code::OutcomeBound, "Recovery outcome already bound") unless old.outcome == outcome.serialize && old.user_id == d.actor.user_id

          return Kirei::Services::Result.new(result: outcome)
        end
        unless row.status == Status::Uncertain || row.status == Status::Sending
          return failure(Code::RecoveryRejected, "Instruction does not require uncertain-send recovery")
        end

        job = @jobs.find_by_key(dispatch_key: "followup:#{id}")
        lease_expires_at = job&.lease_expires_at
        if job&.status == Platform::Jobs::Dto::JobStatus::Running && lease_expires_at && lease_expires_at > Time.now
          return failure(Code::LeaseLive, "Send still holds a live lease")
        end

        s = settled_session(row, w)
        return failure(Code::SessionUnsettled, "Same conversation must be positively settled") unless s

        @transaction.call do
          details = Domains::Commander::Dto::FollowupRecoveryAudit.new(inbox_id: inbox_id, followup_id: id, workflow_id: w.id, session_id: s.id,
                                                                       generation: s.generation, user_id: d.actor.user_id, outcome: outcome.serialize)
          @audit.record(event_key: receipt_key, action: "human_followup_reconciliation", details: details)
          delivered = outcome == Outcome::Delivered
          @followups.mark(id: id, status: delivered ? Status::Delivered : Status::Blocked, reason: "Human #{outcome.serialize} confirmation at inbox #{inbox_id}; no resend",
                          delivered_at: delivered ? Time.now : nil)
          @jobs.close_reconciled(id: job.id) if job
          message = Messaging::Dto::OutgoingMessage.new(
            channel_id: d.channel_id,
            thread_id: d.thread_id,
            bot: Messaging::Dto::Bot::Agent,
            role: Messaging::Dto::SpeakerRole::Commander,
            body: "Instruction #{id}: human confirmed #{outcome.serialize}; no prompt was resent.",
            key: receipt_key
          )
          Platform::Unwrap.call(@outbox.enqueue(message: message))
        end
        Kirei::Services::Result.new(result: outcome)
      end

      # The follow-up's active Writer of its recorded, latest generation in
      # the same settled conversation, pane alias, worktree and CLI.
      sig { params(row: Domains::Commander::Dto::FollowupView, w: Domains::Workflows::Dto::WorkflowView).returns(T.nilable(Domains::Sessions::Dto::SessionView)) }
      private def settled_session(row, w)
        session_id = row.session_id
        s = session_id && @registry.find(id: session_id)
        s = nil unless s && row.generation == s.generation && s.workflow_id == w.id && s.role == Writer && s.active
        latest = @registry.latest_generation(workflow_id: w.id, role: Writer)
        live = s && @herdr.pane(s.pane_id)
        return nil unless s && live && latest == row.generation && Identity.same?(s.runtime_identity, live.agent_session)
        return nil unless live.agent_status.settled? && live.name == s.alias && live.cwd == w.worktree_path && live.agent == s.configuration.cli

        s
      end

      sig { params(code: Code, detail: String).returns(Result) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
