# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    # Routes a verified human message to exactly one active workflow's Writer
    # session, once per inbox record. The target comes from the workflow
    # thread, a human route selection, a grounded Commander interpretation, or
    # the human's recent thread binding. Anything else asks for clarification.
    # A selection is a human clarification, not a model's authority to invent
    # workflow or session ids.
    class RouteFollowup
      extend T::Sig

      Code = Dto::ErrorCode
      Workflow = Domains::Workflows::Dto::WorkflowView
      Messaging = Domains::Messaging
      Commander = Domains::Commander
      Writer = Domains::Sessions::Dto::SessionRole::Writer
      Outcome = T.type_alias { Kirei::Services::Result[Dto::RouteOutcome] }
      CONTEXT_SECONDS = 1800
      COMMANDER_THREAD = "commander"

      sig do
        params(resolver: Messaging::DeliveryVerifier, membership: Messaging::MembershipCheck, handle: String,
               commander_channel_id: T.nilable(String), now: T.proc.returns(Time), followups: Commander::Followups, bindings: Commander::Bindings, inbox: Messaging::Inbox,
               outbox: Messaging::Outbox, catalog: Domains::Workflows::Catalog, registry: Domains::Sessions::Registry,
               renewals: Domains::Sessions::Renewals, jobs: Platform::Jobs::Store, transaction: Platform::Transaction).void
      end
      def initialize(resolver:, membership:, handle:, commander_channel_id:, now: -> { Time.now },
                     followups: Commander::Followups.new, bindings: Commander::Bindings.new, inbox: Messaging::Inbox.new, outbox: Messaging::Outbox.new,
                     catalog: Domains::Workflows::Catalog.new, registry: Domains::Sessions::Registry.new, renewals: Domains::Sessions::Renewals.new,
                     jobs: Platform::Jobs::Store.new, transaction: Platform::Transaction.new)
        @resolver = resolver
        @membership = membership
        @now = now
        @handle = handle
        @commander_channel = commander_channel_id
        @followups = followups
        @bindings = bindings
        @inbox = inbox
        @outbox = outbox
        @catalog = catalog
        @registry = registry
        @renewals = renewals
        @jobs = jobs
        @transaction = transaction
      end

      sig do
        params(inbox_id: String, selection: T.nilable(String), interpretation: T.nilable(Commander::Dto::RoutingInterpretation), clarify: T::Boolean, forwarded: T::Boolean)
          .returns(Outcome)
      end
      def call(inbox_id:, selection: nil, interpretation: nil, clarify: true, forwarded: false)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          source = @inbox.find(id: inbox_id)
          next failure(Code::MissingSource, "Missing source") unless source

          d = posted(source)
          unless d.post_revision == source.post_revision && d.actor.user_id == source.user_id && d.body == source.verified_delivery.body
            next failure(Code::SourceChanged, "Source changed")
          end
          next failure(Code::SourceChanged, "Human member required") unless d.actor.member && !d.actor.bot

          workflows = active
          interpreted = nil
          if interpretation
            target = find(workflows, interpretation.workflow_id)
            ids = interpretation.evidence_inbox_ids
            next failure(Code::InterpretationRejected, "Interpretation requires cited task evidence") unless target && !ids.empty? && ids.size <= 10
            unless ids.any? { |evidence_id| grounded?(evidence_id, target, d.actor.user_id) }
              next failure(Code::InterpretationRejected, "Interpretation is not grounded in accessible recent task context")
            end

            interpreted = target
          end
          allowed_channels = workflows.map(&:channel_id).uniq.select { |channel| @membership.member?(channel_id: channel, user_id: d.actor.user_id) }
          @transaction.call { route(inbox_id, d, selection, interpretation, interpreted, allowed_channels, clarify, forwarded) }
        end
      end

      sig do
        params(inbox_id: String, d: Messaging::Dto::VerifiedDelivery, selection: T.nilable(String), interpretation: T.nilable(Commander::Dto::RoutingInterpretation),
               interpreted: T.nilable(Workflow), allowed_channels: T::Array[String], clarify: T::Boolean, forwarded: T::Boolean).returns(Outcome)
      end
      private def route(inbox_id, d, selection, interpretation, interpreted, allowed_channels, clarify, forwarded)
        @inbox.lock(id: inbox_id)
        existing = @followups.for_inbox(inbox_id: inbox_id)
        return routed(existing) if existing

        workflows = active
        direct = workflows.find { |workflow| workflow.channel_id == d.channel_id && workflow.thread_id == d.thread_id }
        commander_root = d.root_post && d.channel_id == @commander_channel
        binding = @bindings.find(channel_id: d.channel_id, thread_id: d.thread_id, user_id: d.actor.user_id)
        binding ||= @bindings.find(channel_id: d.channel_id, thread_id: COMMANDER_THREAD, user_id: d.actor.user_id) if commander_root
        recent = T.let(nil, T.nilable(Workflow))
        recent_binding = T.let(nil, T.nilable(String))
        if binding && binding.updated_at > @now.call - CONTEXT_SECONDS
          recent = find(workflows, binding.workflow_id)
          recent_binding = binding.inbox_id if recent
        end
        if selection && !d.body.start_with?("@#{@handle} route #{selection}\n")
          return failure(Code::SelectionRejected, "Selection requires an exact human routing command")
        end

        selected = selection && find(workflows, selection)
        return failure(Code::SelectionRejected, "Inactive selection") if selection && !selected

        targets = [direct, selected, interpreted, selected || interpreted ? nil : recent].compact.uniq(&:id)
        if targets.size != 1
          acknowledge(d, inbox_id, "Which project thread should receive this instruction? Please select the workflow.", "clarification") if clarify
          return Kirei::Services::Result.new(result: Dto::RouteOutcome.new(followup: nil))
        end
        w = @catalog.find_for_update(id: T.must(targets.first).id)
        return failure(Code::InactiveWorkflow, "Workflow became inactive") if !w || w.archived_at || w.phase.terminal?
        return failure(Code::MembershipRequired, "Destination membership required") unless allowed_channels.include?(w.channel_id)

        session = writer_session(w)
        @renewals.schedule(session: session) if session&.active && session.credential_expires_at <= @now.call
        evidence = Commander::Dto::RoutingEvidence.new(source_inbox_id: inbox_id, selection: selection, interpretation: interpretation,
                                                       direct_thread: direct&.id, recent_binding: recent_binding,
                                                       attribution: Commander::Dto::InstructionAttribution.new(
                                                         effective_sender: forwarded ? "Commander" : d.actor.user_id, origin_inbox_id: inbox_id,
                                                         origin_user_id: d.actor.user_id, mode: forwarded ? "commander_forwarded" : "direct_human"
                                                       ))
        followup = Platform::Unwrap.call(@followups.create(inbox_id: inbox_id, workflow_id: w.id, session: session, evidence: evidence))
        threads = [d.thread_id]
        threads << COMMANDER_THREAD if commander_root
        @bindings.bind(channel_id: d.channel_id, thread_ids: threads, user_id: d.actor.user_id, workflow_id: w.id, inbox_id: inbox_id, at: @now.call)
        notice = session ? "Instruction #{followup.id} queued for the existing project session; delivery is pending." : "Instruction #{followup.id} recorded; session reconciliation is required before delivery."
        acknowledge(d, inbox_id, notice, "queued")
        if session
          @jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::SessionFollowup, payload: Commander::Dto::FollowupJob.new(followup_id: followup.id),
                        dispatch_key: "followup:#{followup.id}")
        end
        routed(T.must(@followups.find(id: followup.id)))
      end

      # The one active Writer, or else the one Writer still starting.
      sig { params(workflow: Workflow).returns(T.nilable(Domains::Sessions::Dto::SessionView)) }
      private def writer_session(workflow)
        sessions = @registry.active(workflow_id: workflow.id, role: Writer)
        return sessions.size == 1 ? sessions.first : nil unless sessions.empty?

        starting = @registry.pending_starts(workflow_id: workflow.id, role: Writer).reject(&:active)
        starting.size == 1 ? starting.first : nil
      end

      # Cited evidence counts when it is recent, accessible to the human,
      # still verifies, and belongs to the target's thread, binding or source.
      sig { params(evidence_id: String, target: Workflow, user_id: String).returns(T::Boolean) }
      private def grounded?(evidence_id, target, user_id)
        evidence = @inbox.find(id: evidence_id)
        return false unless evidence && evidence.created_at > @now.call - CONTEXT_SECONDS && @membership.member?(channel_id: evidence.channel_id, user_id: user_id)

        verified = posted(evidence)
        same = verified.post_revision == evidence.post_revision && verified.actor.user_id == evidence.user_id && verified.body == evidence.verified_delivery.body
        return false unless same && verified.actor.member && !verified.actor.bot

        direct_evidence = evidence.channel_id == target.channel_id && evidence.thread_id == target.thread_id
        direct_evidence || @bindings.bound?(inbox_id: evidence_id, workflow_id: target.id) || target.source_inbox_id == evidence_id
      end

      sig { params(record: Messaging::Dto::InboxRecord).returns(Messaging::Dto::VerifiedDelivery) }
      private def posted(record)
        @resolver.delivery(post_id: record.post_id, channel_id: record.channel_id, event_kind: Messaging::Dto::EventKind::Posted)
      end

      # Routable workflows: not archived and not closed or cancelled.
      sig { returns(T::Array[Workflow]) }
      private def active = @catalog.active.reject { |workflow| workflow.phase.terminal? }

      sig { params(workflows: T::Array[Workflow], id: String).returns(T.nilable(Workflow)) }
      private def find(workflows, id) = workflows.find { |workflow| workflow.id == id }

      sig { params(d: Messaging::Dto::VerifiedDelivery, id: String, text: String, kind: String).void }
      private def acknowledge(d, id, text, kind)
        message = Messaging::Dto::OutgoingMessage.new(channel_id: d.channel_id, thread_id: d.thread_id, bot: Messaging::Dto::Bot::Commander,
                                                      role: Messaging::Dto::SpeakerRole::Commander, body: text, key: "commander:#{id}:#{kind}")
        Platform::Unwrap.call(@outbox.enqueue(message: message))
      end

      sig { params(followup: Commander::Dto::FollowupView).returns(Outcome) }
      private def routed(followup) = Kirei::Services::Result.new(result: Dto::RouteOutcome.new(followup: followup))

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
