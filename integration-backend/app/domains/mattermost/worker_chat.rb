# frozen_string_literal: true

require "digest"
module Domains
  module Mattermost
    class WorkerChat
      def initialize(db) = @db = db

      def post(token:, generation:, body:, key:)
        raise ArgumentError,
              "Invalid callback" unless token.is_a?(String) && !token.empty? && generation.is_a?(Integer) && body.is_a?(String) && body.bytesize.between?(
                1, 60_000
              ) && key.is_a?(String) && key.match?(/\A[A-Za-z0-9_.:-]{1,200}\z/)

        @db.transaction do
          session = @db[:sessions].where(credential_digest: Digest::SHA256.hexdigest(token), generation: generation,
                                         active: true).for_update.first
          raise ArgumentError,
                "Invalid or stale session" unless session && session[:credential_expires_at] > Time.now && %w[
                  writer reviewer
                ].include?(session[:role])

          workflow = @db[:workflows].where(id: session[:workflow_id]).for_update.first
          raise ArgumentError, "Inactive workflow" unless workflow && workflow[:archived_at].nil? && !%w[cancelled
                                                                                                         closed].include?(workflow[:phase])

          phase = workflow[:phase] == "paused" ? workflow[:saved_phase] : workflow[:phase]
          allowed_role = if %w[spec_review plan_review implementation_review].include?(phase)
                           "reviewer"
                         elsif %w[spec_writing spec_human_approval plan_writing plan_human_approval implementation pr_ready done].include?(phase)
                           "writer"
                         end
          raise ArgumentError, "Session role is not active in this phase" unless session[:role] == allowed_role

          latest = @db[:sessions].where(workflow_id: session[:workflow_id], role: session[:role]).max(:generation)
          raise ArgumentError, "Stale session generation" unless latest == generation

          digest = Digest::SHA256.hexdigest(body)
          @db[:callbacks].insert_conflict(target: [:session_id, :generation, :key]).insert(session_id: session[:id],
                                                                                           generation: generation, key: key, body_digest: digest)
          callback = @db[:callbacks][session_id: session[:id], generation: generation, key: key]
          raise ArgumentError, "Callback key reused with changed body" unless callback[:body_digest] == digest

          Outbox.new(@db).enqueue(channel_id: workflow[:channel_id], thread_id: workflow[:thread_id], bot: "worker",
                                  role: session[:role], body: "[#{session[:role]}] #{body}", key: "callback:#{session[:id]}:#{generation}:#{key}")
          result("accepted", "Queued in bound thread")
        end
      rescue ArgumentError => e
        result("rejected", e.message)
      end
      private def result(status, reason)
        Domains::Workflows::Entities::Outcome.new(status: status, reason: reason)
      end
    end
  end
end
