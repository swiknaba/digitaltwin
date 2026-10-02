# frozen_string_literal: true

module Domains
  module Controller
    class Routing
      TERMINAL = %w[closed cancelled].freeze
      def initialize(db, resolver:, membership:, now: -> { Time.now }, approvals: nil, handle: ENV.fetch("AGENT_HANDLE", "agent"))
        @db, @resolver, @membership, @now, @approvals, @handle = db, resolver, membership, now, approvals, handle
      end

      # Only verified inbox identities enter this service. Selection is a human
      # clarification, not a model's authority to invent workflow/session IDs.
      def route(inbox_id:, selection: nil)
        source = @db[:inbox][id: inbox_id] or raise ArgumentError, "Missing source"
        d = @resolver.delivery(post_id: source[:post_id], channel_id: source[:channel_id], event_kind: "posted")
        raise ArgumentError, "Source changed" unless d.post_revision == source[:post_revision] && d.actor.user_id == source[:user_id]
        raise ArgumentError, "Human member required" unless d.actor.member && !d.actor.bot

        allowed_channels = active.select_map(:channel_id).uniq.select { |channel| @membership.call(channel, d.actor.user_id) }
        @db.transaction do
          @db[:inbox].where(id: inbox_id).for_update.first
          existing = @db[:followups][inbox_id: inbox_id]
          return existing if existing

          direct = active.where(channel_id: d.channel_id, thread_id: d.thread_id).first
          binding = @db[:conversation_bindings][channel_id: d.channel_id, thread_id: d.thread_id, user_id: d.actor.user_id]
          recent = binding && binding[:updated_at] > @now.call - 1800 && active[id: binding[:workflow_id]]
          raise ArgumentError, "Selection requires an exact human routing command" if selection && !d.body.start_with?("@#{@handle} route #{selection}\n")

          selected = selection && active[id: selection]
          raise ArgumentError, "Inactive selection" if selection && !selected

          targets = [direct, selected, selected ? nil : recent].select { |w| w.is_a?(Hash) }.uniq { |w| w[:id] }
          if targets.size != 1
            acknowledge(d, inbox_id, "Which project thread should receive this instruction? Please select the workflow.", "clarification")
            return { status: "clarification" }
          end
          w = @db[:workflows].where(id: targets.first[:id]).for_update.first
          raise ArgumentError, "Workflow became inactive" if w[:archived_at] || TERMINAL.include?(w[:phase])
          raise ArgumentError, "Destination membership required" unless allowed_channels.include?(w[:channel_id])

          sessions = @db[:sessions].where(workflow_id: w[:id], role: "writer", active: true).all
          session = sessions.size == 1 ? sessions.first : nil
          session = nil if session && session[:credential_expires_at] <= @now.call
          evidence = { "source_inbox_id" => inbox_id, "selection" => selection,
                       "direct_thread" => direct && direct[:id], "recent_binding" => recent && binding[:inbox_id] }
          id = @db[:followups].insert(inbox_id: inbox_id, workflow_id: w[:id], session_id: session && session[:id],
                                      generation: session && session[:generation], evidence: Sequel.pg_jsonb(evidence),
                                      status: session ? "queued" : "blocked", reason: session ? nil : "Session reconciliation required")
          @db[:conversation_bindings].insert_conflict(target: %i[channel_id thread_id user_id], update: {
                                                        workflow_id: w[:id], inbox_id: inbox_id, updated_at: @now.call
                                                      }).insert(channel_id: d.channel_id, thread_id: d.thread_id, user_id: d.actor.user_id,
                                                                workflow_id: w[:id], inbox_id: inbox_id, updated_at: @now.call)
          acknowledge(d, inbox_id, session ? "Instruction queued for the existing project session; delivery is pending." : "Instruction recorded; session reconciliation is required before delivery.", "queued")
          Domains::Jobs::Store.new(@db).enqueue(kind: "session.followup", payload: { "followup_id" => id }, key: "followup:#{id}") if session
          @db[:followups][id: id]
        end
      end

      def call(job, _store)
        id = job[:payload].fetch("inbox_id")
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

      private def active = @db[:workflows].where(archived_at: nil).exclude(phase: TERMINAL)
      private def acknowledge(d, id, text, kind)
        Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: d.channel_id, thread_id: d.thread_id,
                                                     bot: "agent", role: "controller", body: text, key: "master:#{id}:#{kind}")
      end
    end
  end
end
