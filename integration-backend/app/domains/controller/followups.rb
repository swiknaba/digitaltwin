# frozen_string_literal: true

module Domains
  module Controller
    class Followups
      def initialize(db, herdr:, resolver:, membership:, policy: Domains::Workflows::Policy.new, handle: ENV.fetch("AGENT_HANDLE", "agent"))
        @db, @herdr, @resolver, @membership, @policy, @handle = db, herdr, resolver, membership, policy, handle
      end

      # All future review/session transitions must use this same workflow mutex.
      # Keep the connection checked out across commits, never network in a DB tx.
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

            session = @db[:sessions][id: row[:session_id], active: true, generation: row[:generation], workflow_id: w[:id], role: "writer"]
            return block(id, "Session stale; reconcile without creating a session") unless session && session[:credential_expires_at] > Time.now

            pending = @db[:followups].where(workflow_id: w[:id]).where { self.id < id }.where(status: %w[queued sending uncertain]).count
            return "queued" unless pending.zero?

            live = @herdr.get(session[:pane_id])
            return "queued" if live["agent_status"] == "working"

            ready = %w[idle done].include?(live["agent_status"]) && live["interactive_ready"] == true && live["launch_pending"] == false
            identity = live["name"] == session[:alias] && live["cwd"] == w[:worktree_path] && live["agent"] == session[:configuration]["cli"]
            return block(id, "Session not ready") unless ready && identity

            @db[:followups].where(id: id, status: "queued").update(status: "sending")
            begin
              raise IOError, "Dispatch lease lost" unless before_effect.call

              @herdr.prompt(session[:pane_id], source[:verified_delivery].fetch("body").sub(/\A@#{Regexp.escape(@handle)} route [a-zA-Z0-9-]+\n/, ""))
              @db[:followups].where(id: id).update(status: "delivered", delivered_at: Time.now)
              "delivered"
            rescue StandardError
              @db[:followups].where(id: id).update(status: "uncertain", reason: "Socket effect requires reconciliation; do not resend")
              "uncertain"
            end
          ensure
            @db.get(Sequel.function(:pg_advisory_unlock, Sequel.function(:hashtextextended, row[:workflow_id], 0)))
          end
        end
      end

      def call(job, store)
        state = deliver(job[:payload].fetch("followup_id"), before_effect: -> { store.begin_effect(id: job[:id], lease_token: job[:lease_token]) })
        store.block(id: job[:id], lease_token: job[:lease_token], reason: "Follow-up #{state}; reconciliation or gated release required") unless state == "delivered"
      end

      private def block(id, reason)
        @db[:followups].where(id: id).update(status: "blocked", reason: reason)
        "blocked"
      end
    end
  end
end
