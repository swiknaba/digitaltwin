# typed: strict
# frozen_string_literal: true

module Services
  module Master
    # Handles session.followup: prompts the follow-up's Writer session once,
    # in creation order, while the workflow is writing and the same
    # conversation is ready. A follow-up is marked sending before the prompt;
    # a failed send becomes uncertain and is never resent automatically.
    class DeliverFollowup
      extend T::Sig
      include Platform::Jobs::Handler

      Decision = Platform::Jobs::Dto::Decision
      Status = Domains::Commander::Dto::FollowupStatus
      Phase = Domains::Workflows::Dto::Phase
      Messaging = Domains::Messaging
      Identity = Adapters::Herdr::ConversationIdentity
      Writer = Domains::Sessions::Dto::SessionRole::Writer
      Followup = Domains::Commander::Dto::FollowupView

      sig do
        params(herdr: Adapters::Herdr::Client, resolver: Messaging::DeliveryVerifier, membership: Messaging::MembershipCheck, policy: Domains::Workflows::Policy,
               handle: String, followups: Domains::Commander::Followups, inbox: Messaging::Inbox, outbox: Messaging::Outbox,
               catalog: Domains::Workflows::Catalog, registry: Domains::Sessions::Registry, operations: Domains::Sessions::Operations,
               renewals: Domains::Sessions::Renewals, jobs: Platform::Jobs::Store, lock: Platform::Lock, transaction: Platform::Transaction).void
      end
      def initialize(herdr:, resolver:, membership:, policy: Domains::Workflows::Policy.new, handle: ENV.fetch("AGENT_HANDLE", "agent"),
                     followups: Domains::Commander::Followups.new, inbox: Messaging::Inbox.new, outbox: Messaging::Outbox.new,
                     catalog: Domains::Workflows::Catalog.new, registry: Domains::Sessions::Registry.new, operations: Domains::Sessions::Operations.new,
                     renewals: Domains::Sessions::Renewals.new, jobs: Platform::Jobs::Store.new, lock: Platform::Lock.new, transaction: Platform::Transaction.new)
        @herdr = herdr
        @resolver = resolver
        @membership = membership
        @policy = policy
        @handle = handle
        @followups = followups
        @inbox = inbox
        @outbox = outbox
        @catalog = catalog
        @registry = registry
        @operations = operations
        @renewals = renewals
        @jobs = jobs
        @lock = lock
        @transaction = transaction
      end

      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          status = deliver(followup_id(job), job.lease)
          if status == Status::Queued && @policy.dispatch_allowed?
            Decision.defer("Waiting for workflow/session readiness")
          elsif status != Status::Delivered
            Decision.block("Follow-up #{status.serialize}; reconciliation or gated release required")
          else
            Decision.complete
          end
        end
      end

      # All review and session transitions of a workflow use its
      # Platform::Lock. A busy workflow keeps the follow-up queued. The
      # connection stays checked out across commits; no network call runs in
      # a transaction.
      sig { params(id: String, lease: Platform::Jobs::Lease).returns(Status) }
      private def deliver(id, lease)
        row = @followups.find(id: id) or raise ArgumentError, "Missing instruction"
        @lock.call(key: row.workflow_id) { deliver_locked(id, lease) }
      rescue Platform::Lock::Busy
        Status::Queued
      end

      sig { params(id: String, lease: Platform::Jobs::Lease).returns(Status) }
      private def deliver_locked(id, lease)
        row = T.must(@followups.find(id: id))
        return row.status unless row.status == Status::Queued
        return Status::Queued unless @policy.dispatch_allowed?

        w = T.must(@catalog.find(id: row.workflow_id))
        phase = w.phase
        return Status::Queued if phase == Phase::Paused || phase.review? || phase.human_approval?
        return block(id, "Workflow inactive") if w.archived_at || phase.terminal? || phase == Phase::Blocked
        return Status::Queued unless phase.writing?

        source = T.must(@inbox.find(id: row.inbox_id))
        d = @resolver.delivery(post_id: source.post_id, channel_id: source.channel_id, event_kind: Messaging::Dto::EventKind::Posted)
        valid_source = d.actor.member && !d.actor.bot && d.actor.user_id == source.user_id && d.post_revision == source.post_revision
        valid_source &&= d.body == source.verified_delivery.body && @membership.member?(channel_id: w.channel_id, user_id: d.actor.user_id)
        return block(id, "Source or membership changed") unless valid_source

        session = writer_session(row, w)
        latest = session && @registry.latest_generation(workflow_id: w.id, role: Writer)
        return block(id, "Session stale; reconcile without creating a session") unless session && latest == row.generation

        unless session.active
          pending_start = @operations.for_session(session_id: session.id, kind: Domains::Sessions::Dto::OperationKind::Start)&.state&.pending?
          return pending_start ? Status::Queued : block(id, "Inactive session requires reconciliation")
        end
        if session.credential_expires_at <= Time.now
          renewal = @jobs.find(id: @renewals.schedule(session: session))
          live_renewal = [Platform::Jobs::Dto::JobStatus::Pending, Platform::Jobs::Dto::JobStatus::Running].include?(renewal&.status)
          return live_renewal ? Status::Queued : block(id, "Credential renewal requires reconciliation")
        end
        return Status::Queued if @followups.pending_before?(id: id, workflow_id: w.id)

        live = @herdr.pane(session.pane_id)
        same_conversation = Identity.same?(session.runtime_identity, live.agent_session)
        return Status::Queued if live.agent_status == Adapters::Herdr::Dto::AgentStatus::Working && same_conversation

        ready = live.agent_status.settled? && live.interactive_ready == true && live.launch_pending == false
        identity = same_conversation && live.name == session.alias && live.cwd == w.worktree_path && live.agent == session.configuration.cli
        return block(id, "Session not ready") unless ready && identity

        prompt_writer(id, session, source, lease)
      end

      # Any failure after the follow-up is marked sending may have reached
      # the Writer, so it becomes uncertain and needs human recovery.
      sig { params(id: String, session: Domains::Sessions::Dto::SessionView, source: Messaging::Dto::InboxRecord, lease: Platform::Jobs::Lease).returns(Status) }
      private def prompt_writer(id, session, source, lease)
        @followups.mark(id: id, status: Status::Sending, from: Status::Queued)
        begin
          raise IOError, "Dispatch lease lost" unless lease.begin_effect

          @herdr.prompt(pane_id: session.pane_id, text: source.verified_delivery.body.sub(/\A@#{Regexp.escape(@handle)} route [a-zA-Z0-9_-]+\n/, ""))
          @followups.mark(id: id, status: Status::Delivered, delivered_at: Time.now)
          Status::Delivered
        rescue StandardError
          @transaction.call do
            @followups.mark(id: id, status: Status::Uncertain, reason: "Socket effect requires reconciliation; do not resend")
            message = Messaging::Dto::OutgoingMessage.new(
              channel_id: source.channel_id,
              thread_id: source.thread_id,
              bot: Messaging::Dto::Bot::Agent,
              role: Messaging::Dto::SpeakerRole::Controller,
              body: "Instruction #{id} has an uncertain send result. Inspect this conversation, then use @#{@handle} recover-followup #{id} delivered|discard. No automatic resend.",
              key: "followup:uncertain:#{id}"
            )
            Platform::Unwrap.call(@outbox.enqueue(message: message))
          end
          Status::Uncertain
        end
      end

      # The follow-up's Writer session of exactly its recorded generation.
      sig { params(row: Followup, workflow: Domains::Workflows::Dto::WorkflowView).returns(T.nilable(Domains::Sessions::Dto::SessionView)) }
      private def writer_session(row, workflow)
        session_id = row.session_id
        session = session_id && @registry.find(id: session_id)
        session if session && row.generation == session.generation && session.workflow_id == workflow.id && session.role == Writer
      end

      sig { params(id: String, reason: String).returns(Status) }
      private def block(id, reason)
        @followups.mark(id: id, status: Status::Blocked, reason: reason)
        Status::Blocked
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(String) }
      private def followup_id(job)
        value = Domains::Commander::Dto::FollowupJob.from_hash(job.payload, true).followup_id
        raise ArgumentError, "Follow-up job is malformed" if value.empty?

        value
      end
    end
  end
end
