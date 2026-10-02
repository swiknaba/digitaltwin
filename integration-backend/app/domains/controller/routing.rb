# typed: strict
# frozen_string_literal: true

module Domains
  module Controller
    class Routing
      extend T::Sig
      TERMINAL = T.let(%w[closed cancelled].freeze, T::Array[String])
      Interpretation = T.type_alias { T::Hash[String, Object] }
      sig do
        params(db: Sequel::Database, resolver: Source::DeliveryResolver,
               membership: T.proc.params(channel_id: String, user_id: String).returns(T::Boolean),
               now: T.proc.returns(Time), approvals: T.nilable(Approvals), handle: String,
               master_channel_id: T.nilable(String)).void
      end
      def initialize(db, resolver:, membership:, now: -> { Time.now }, approvals: nil, handle: ENV.fetch("AGENT_HANDLE", "agent"), master_channel_id: ENV["MASTER_CHANNEL_ID"])
        @master_channel = T.let(master_channel_id, T.nilable(String))
        @db = T.let(db, Sequel::Database)
        @resolver = T.let(resolver, Source::DeliveryResolver)
        @membership = T.let(membership, T.proc.params(channel_id: String, user_id: String).returns(T::Boolean))
        @now = T.let(now, T.proc.returns(Time))
        @approvals = T.let(approvals, T.nilable(Approvals))
        @handle = T.let(handle, String)
      end

      # Only verified inbox identities enter this service. Selection is a human
      # clarification, not a model's authority to invent workflow/session IDs.
      sig { params(inbox_id: T.any(Integer, String), selection: T.nilable(String), interpretation: T.nilable(Interpretation), clarify: T::Boolean).returns(Object) }
      def route(inbox_id:, selection: nil, interpretation: nil, clarify: true)
        source = @db[:inbox][id: inbox_id] or raise ArgumentError, "Missing source"
        d = @resolver.delivery(post_id: source[:post_id], channel_id: source[:channel_id], event_kind: "posted")
        raise ArgumentError, "Source changed" unless d.post_revision == source[:post_revision] && d.actor.user_id == source[:user_id] && d.body == source[:verified_delivery]["body"]
        raise ArgumentError, "Human member required" unless d.actor.member && !d.actor.bot

        interpreted = nil
        if interpretation
          target = active[id: interpretation.fetch("workflow_id")]
          ids = interpretation.fetch("evidence_inbox_ids")
          raise ArgumentError, "Interpretation requires cited task evidence" unless target && ids.is_a?(Array) && !ids.empty? && ids.size <= 10

          grounded = ids.any? do |evidence_id|
            evidence = @db[:inbox][id: evidence_id]
            next false unless evidence && evidence[:created_at] > @now.call - 1800 && @membership.call(evidence[:channel_id], d.actor.user_id)

            verified = @resolver.delivery(post_id: evidence[:post_id], channel_id: evidence[:channel_id], event_kind: "posted")
            next false unless verified.post_revision == evidence[:post_revision] && verified.actor.user_id == evidence[:user_id] && verified.body == evidence[:verified_delivery]["body"] && verified.actor.member && !verified.actor.bot

            direct_evidence = evidence[:channel_id] == target[:channel_id] && evidence[:thread_id] == target[:thread_id]
            bound_evidence = @db[:conversation_bindings][inbox_id: evidence_id, workflow_id: target[:id]]
            direct_evidence || bound_evidence || target[:source_inbox_id] == evidence_id
          end
          raise ArgumentError, "Interpretation is not grounded in accessible recent task context" unless grounded

          interpreted = target
        end
        conversation_thread = d.thread_id
        allowed_channels = active.select_map(:channel_id).uniq.select { |channel| @membership.call(channel, d.actor.user_id) }
        @db.transaction do
          @db[:inbox].where(id: inbox_id).for_update.first
          existing = @db[:followups][inbox_id: inbox_id]
          return existing if existing

          direct = active.where(channel_id: d.channel_id, thread_id: d.thread_id).first
          binding = @db[:conversation_bindings][channel_id: d.channel_id, thread_id: conversation_thread, user_id: d.actor.user_id]
          if !binding && d.root_post && d.channel_id == @master_channel
            binding = @db[:conversation_bindings][channel_id: d.channel_id, thread_id: "master", user_id: d.actor.user_id]
          end
          recent = binding && binding[:updated_at] > @now.call - 1800 && active[id: binding[:workflow_id]]
          raise ArgumentError, "Selection requires an exact human routing command" if selection && !d.body.start_with?("@#{@handle} route #{selection}\n")

          selected = selection && active[id: selection]
          raise ArgumentError, "Inactive selection" if selection && !selected

          targets = [direct, selected, interpreted, (selected || interpreted) ? nil : recent].select { |w| w.is_a?(Hash) }.uniq { |w| w[:id] }
          if targets.size != 1
            acknowledge(d, inbox_id, "Which project thread should receive this instruction? Please select the workflow.", "clarification") if clarify
            return { status: "clarification" }
          end
          w = @db[:workflows].where(id: targets.first[:id]).for_update.first
          raise ArgumentError, "Workflow became inactive" if w[:archived_at] || TERMINAL.include?(w[:phase])
          raise ArgumentError, "Destination membership required" unless allowed_channels.include?(w[:channel_id])

          sessions = @db[:sessions].where(workflow_id: w[:id], role: "writer", active: true).all
          session = sessions.size == 1 ? sessions.first : nil
          if sessions.empty?
            starting = @db[:sessions].where(workflow_id: w[:id], role: "writer", active: false).join(:session_operations, session_id: :id).where(Sequel[:session_operations][:kind] => "start",
                                                                                                                                                 Sequel[:session_operations][:state] => %w[
                                                                                                                                                   queued sending uncertain
                                                                                                                                                 ]).select_all(:sessions).all
            session = starting.first if starting.size == 1
          end
          Domains::Sessions::Lifecycle.schedule_renewal(@db, session) if session && session[:active] && session[:credential_expires_at] <= @now.call
          evidence = { "source_inbox_id" => inbox_id, "selection" => selection, "interpretation" => interpretation,
                       "direct_thread" => direct && direct[:id], "recent_binding" => recent && binding[:inbox_id] }
          id = @db[:followups].insert(inbox_id: inbox_id, workflow_id: w[:id], session_id: session && session[:id],
                                      generation: session && session[:generation], evidence: Sequel.pg_jsonb(evidence),
                                      status: session ? "queued" : "blocked", reason: session ? nil : "Session reconciliation required")
          threads = [conversation_thread]
          threads << "master" if d.root_post && d.channel_id == @master_channel
          threads.each do |context_thread|
            @db[:conversation_bindings].insert_conflict(target: %i[channel_id thread_id user_id], update: {
                                                          workflow_id: w[:id], inbox_id: inbox_id, updated_at: @now.call
                                                        }).insert(channel_id: d.channel_id, thread_id: context_thread, user_id: d.actor.user_id,
                                                                  workflow_id: w[:id], inbox_id: inbox_id, updated_at: @now.call)
          end
          acknowledge(d, inbox_id, session ? "Instruction #{id} queued for the existing project session; delivery is pending." : "Instruction #{id} recorded; session reconciliation is required before delivery.", "queued")
          Domains::Jobs::Store.new(@db).enqueue(kind: "session.followup", payload: { "followup_id" => id }, key: "followup:#{id}") if session
          @db[:followups][id: id]
        end
      end

      sig { params(job: Domains::Jobs::Store::Job, _store: Domains::Jobs::Store).void }
      def call(job, _store)
        id = inbox_id(job)
        body = @db[:inbox][id: id][:verified_delivery].fetch("body")
        approval = body.match(/\A@#{Regexp.escape(@handle)} approve ([a-zA-Z0-9-]+) (spec|plan) ([0-9a-f]{40})\z/)
        if approval
          raise ArgumentError, "Approval service unavailable" unless @approvals

          @approvals.record(inbox_id: id, workflow_id: approval[1], gate: approval[2], commit: approval[3])
          source = @db[:inbox][id: id]
          Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: source[:channel_id], thread_id: source[:thread_id],
                                                       bot: "agent", role: "controller", body: "#{approval[2]} approval recorded for #{approval[1]} at #{approval[3]}.", key: "master:#{id}:approval")
          return
        end
        selection = body[/\A@#{Regexp.escape(@handle)} route ([a-zA-Z0-9-]+)\n.+/m, 1]
        route(inbox_id: id, selection: selection)
      end

      sig { returns(Sequel::Dataset) }
      private def active = @db[:workflows].where(archived_at: nil).exclude(phase: TERMINAL)

      sig { params(d: Domains::Mattermost::VerifiedDelivery, id: T.any(Integer, String), text: String, kind: String).returns(String) }
      private def acknowledge(d, id, text, kind)
        Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: d.channel_id, thread_id: d.thread_id,
                                                     bot: "agent", role: "controller", body: text, key: "master:#{id}:#{kind}")
      end

      sig { params(job: Domains::Jobs::Store::Job).returns(T.any(Integer, String)) }
      private def inbox_id(job)
        value = job.payload.fetch("inbox_id") { raise ArgumentError, "Routing job is malformed" }
        raise ArgumentError, "Routing job is malformed" unless value.is_a?(Integer) || value.is_a?(String)

        value
      end
    end
  end
end
