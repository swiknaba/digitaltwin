# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    class Routing
      extend T::Sig

      Workflow = Domains::Workflows::Dto::WorkflowView
      Interpretation = T.type_alias { T::Hash[String, Object] }
      sig do
        params(db: Sequel::Database, resolver: Domains::Messaging::DeliveryVerifier,
               membership: T.proc.params(channel_id: String, user_id: String).returns(T::Boolean),
               now: T.proc.returns(Time), approvals: T.nilable(Approvals), handle: String,
               master_channel_id: T.nilable(String)).void
      end
      def initialize(db, resolver:, membership:, now: -> { Time.now }, approvals: nil, handle: ENV.fetch("AGENT_HANDLE", "agent"), master_channel_id: ENV["MASTER_CHANNEL_ID"])
        @master_channel = master_channel_id
        @db = db
        @resolver = resolver
        @membership = membership
        @now = now
        @approvals = approvals
        @handle = handle
        @inbox = T.let(Domains::Messaging::Inbox.new, Domains::Messaging::Inbox)
        @catalog = T.let(Domains::Workflows::Catalog.new, Domains::Workflows::Catalog)
      end

      # Only verified inbox identities enter this service. Selection is a human
      # clarification, not a model's authority to invent workflow/session IDs.
      sig { params(inbox_id: String, selection: T.nilable(String), interpretation: T.nilable(Interpretation), clarify: T::Boolean).returns(Object) }
      def route(inbox_id:, selection: nil, interpretation: nil, clarify: true)
        source = @inbox.find(id: inbox_id) or raise ArgumentError, "Missing source"
        d = @resolver.delivery(post_id: source.post_id, channel_id: source.channel_id, event_kind: Domains::Messaging::Dto::EventKind::Posted)
        raise ArgumentError, "Source changed" unless d.post_revision == source.post_revision && d.actor.user_id == source.user_id && d.body == source.verified_delivery.body
        raise ArgumentError, "Human member required" unless d.actor.member && !d.actor.bot

        interpreted = nil
        workflows = active
        if interpretation
          target = find(workflows, interpretation.fetch("workflow_id"))
          ids = interpretation.fetch("evidence_inbox_ids")
          raise ArgumentError, "Interpretation requires cited task evidence" unless target && ids.is_a?(Array) && !ids.empty? && ids.size <= 10

          grounded = ids.any? do |evidence_id|
            evidence = @inbox.find(id: evidence_id)
            next false unless evidence && evidence.created_at > @now.call - 1800 && @membership.call(evidence.channel_id, d.actor.user_id)

            verified = @resolver.delivery(post_id: evidence.post_id, channel_id: evidence.channel_id, event_kind: Domains::Messaging::Dto::EventKind::Posted)
            next false unless verified.post_revision == evidence.post_revision && verified.actor.user_id == evidence.user_id && verified.body == evidence.verified_delivery.body && verified.actor.member && !verified.actor.bot

            direct_evidence = evidence.channel_id == target.channel_id && evidence.thread_id == target.thread_id
            bound_evidence = @db[:conversation_bindings][inbox_id: evidence_id, workflow_id: target.id]
            direct_evidence || bound_evidence || target.source_inbox_id == evidence_id
          end
          raise ArgumentError, "Interpretation is not grounded in accessible recent task context" unless grounded

          interpreted = target
        end
        conversation_thread = d.thread_id
        allowed_channels = workflows.map(&:channel_id).uniq.select { |channel| @membership.call(channel, d.actor.user_id) }
        @db.transaction do
          @inbox.lock(id: inbox_id)
          existing = @db[:followups][inbox_id: inbox_id]
          return existing if existing

          workflows = active
          direct = workflows.find { |workflow| workflow.channel_id == d.channel_id && workflow.thread_id == d.thread_id }
          binding = @db[:conversation_bindings][channel_id: d.channel_id, thread_id: conversation_thread, user_id: d.actor.user_id]
          if !binding && d.root_post && d.channel_id == @master_channel
            binding = @db[:conversation_bindings][channel_id: d.channel_id, thread_id: "master", user_id: d.actor.user_id]
          end
          recent = binding && binding[:updated_at] > @now.call - 1800 && find(workflows, binding[:workflow_id])
          raise ArgumentError, "Selection requires an exact human routing command" if selection && !d.body.start_with?("@#{@handle} route #{selection}\n")

          selected = selection && find(workflows, selection)
          raise ArgumentError, "Inactive selection" if selection && !selected

          targets = [direct, selected, interpreted, (selected || interpreted) ? nil : recent].grep(Workflow).uniq(&:id)
          if targets.size != 1
            acknowledge(d, inbox_id, "Which project thread should receive this instruction? Please select the workflow.", "clarification") if clarify
            return { status: "clarification" }
          end
          w = @catalog.find_for_update(id: T.must(targets.first).id)
          raise ArgumentError, "Workflow became inactive" if !w || w.archived_at || w.phase.terminal?
          raise ArgumentError, "Destination membership required" unless allowed_channels.include?(w.channel_id)

          sessions = @db[:sessions].where(workflow_id: w.id, role: "writer", active: true).all
          session = sessions.size == 1 ? sessions.first : nil
          if sessions.empty?
            starting = @db[:sessions].where(workflow_id: w.id, role: "writer", active: false).join(:session_operations, session_id: :id).where(Sequel[:session_operations][:kind] => "start",
                                                                                                                                               Sequel[:session_operations][:state] => %w[
                                                                                                                                                 queued sending uncertain
                                                                                                                                               ]).select_all(:sessions).all
            session = starting.first if starting.size == 1
          end
          Domains::Sessions::Lifecycle.schedule_renewal(@db, session) if session && session[:active] && session[:credential_expires_at] <= @now.call
          evidence = { "source_inbox_id" => inbox_id, "selection" => selection, "interpretation" => interpretation,
                       "direct_thread" => direct&.id, "recent_binding" => recent && binding[:inbox_id] }
          id = @db[:followups].insert(id: Platform::HumanId.call(prefix: "followup"), inbox_id: inbox_id, workflow_id: w.id, session_id: session && session[:id],
                                      generation: session && session[:generation], evidence: Sequel.pg_jsonb(evidence),
                                      status: session ? "queued" : "blocked", reason: session ? nil : "Session reconciliation required")
          threads = [conversation_thread]
          threads << "master" if d.root_post && d.channel_id == @master_channel
          threads.each do |context_thread|
            @db[:conversation_bindings].insert_conflict(target: %i[channel_id thread_id user_id], update: {
                                                          workflow_id: w.id, inbox_id: inbox_id, updated_at: @now.call
                                                        }).insert(channel_id: d.channel_id, thread_id: context_thread, user_id: d.actor.user_id,
                                                                  workflow_id: w.id, inbox_id: inbox_id, updated_at: @now.call)
          end
          acknowledge(d, inbox_id, session ? "Instruction #{id} queued for the existing project session; delivery is pending." : "Instruction #{id} recorded; session reconciliation is required before delivery.", "queued")
          Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::SessionFollowup, payload: Dto::FollowupJob.new(followup_id: id), dispatch_key: "followup:#{id}") if session
          @db[:followups][id: id]
        end
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        id = Dto::InboxDispatchJob.from_hash(job.payload, true).inbox_id
        source = T.must(@inbox.find(id: id))
        body = source.verified_delivery.body
        command = ::Services::Commands::Parser.new.call(body: body, agent_handle: @handle, worker_handle: ENV.fetch("WORKER_HANDLE", "worker"))
        if command.is_a?(::Services::Commands::Dto::Approve)
          raise ArgumentError, "Approval service unavailable" unless @approvals

          gate = command.gate.serialize
          @approvals.record(inbox_id: id, workflow_id: command.workflow_id, gate: gate, commit: command.commit)
          notify(channel_id: source.channel_id, thread_id: source.thread_id, body: "#{gate} approval recorded for #{command.workflow_id} at #{command.commit}.", key: "master:#{id}:approval")
          return Platform::Jobs::Dto::Decision.complete
        end
        selection = command.is_a?(::Services::Commands::Dto::Route) ? command.workflow_id : nil
        route(inbox_id: id, selection: selection)
        Platform::Jobs::Dto::Decision.complete
      end

      # Routable workflows: not archived and not closed or cancelled.
      sig { returns(T::Array[Workflow]) }
      private def active = @catalog.active.reject { |workflow| workflow.phase.terminal? }

      # Model and binding ids are untyped input; only an exact id string matches.
      sig { params(workflows: T::Array[Workflow], id: BasicObject).returns(T.nilable(Workflow)) }
      private def find(workflows, id) = workflows.find { |workflow| workflow.id == id }

      sig { params(d: Domains::Messaging::Dto::VerifiedDelivery, id: String, text: String, kind: String).returns(String) }
      private def acknowledge(d, id, text, kind)
        notify(channel_id: d.channel_id, thread_id: d.thread_id, body: text, key: "master:#{id}:#{kind}")
      end

      sig { params(channel_id: String, thread_id: T.nilable(String), body: String, key: String).returns(String) }
      private def notify(channel_id:, thread_id:, body:, key:)
        message = Domains::Messaging::Dto::OutgoingMessage.new(channel_id: channel_id, thread_id: thread_id, bot: Domains::Messaging::Dto::Bot::Agent,
                                                               role: Domains::Messaging::Dto::SpeakerRole::Controller, body: body, key: key)
        Platform::Unwrap.call(Domains::Messaging::Outbox.new.enqueue(message: message))
      end
    end
  end
end
