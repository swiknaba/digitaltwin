# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    # Handles review.release: once the workflow is back in a writing phase,
    # routes its queued human messages in order and requeues its blocked
    # follow-ups. A message whose source is rejected stays queued and is
    # audited; a transient Mattermost failure stops the release and raises
    # after the follow-ups are requeued, so the job retries.
    class ReleaseQueued
      extend T::Sig
      include Platform::Jobs::Handler

      Decision = Platform::Jobs::Dto::Decision
      RequestFailed = Adapters::Mattermost::Errors::RequestFailed

      # `db` reads raw `followups` until Task 9 adds the commander model.
      sig do
        params(db: Sequel::Database, routing: Domains::Commander::Routing, catalog: Domains::Workflows::Catalog,
               queued_messages: Domains::Workflows::QueuedMessages, jobs: Platform::Jobs::Store, audit: Platform::Audit::Log).void
      end
      def initialize(db, routing:, catalog: Domains::Workflows::Catalog.new, queued_messages: Domains::Workflows::QueuedMessages.new,
                     jobs: Platform::Jobs::Store.new, audit: Platform::Audit::Log.new)
        @db = db
        @routing = routing
        @catalog = catalog
        @queued_messages = queued_messages
        @jobs = jobs
        @audit = audit
      end

      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          release(Domains::Reviews::Dto::ReviewReleaseJob.from_hash(job.payload, true).workflow_id)
          Decision.complete
        end
      end

      sig { params(workflow_id: String).void }
      private def release(workflow_id)
        workflow = @catalog.find(id: workflow_id) or raise ArgumentError, Domains::Reviews::Rounds::MALFORMED
        return unless workflow.phase.writing?

        transient = T.let(nil, T.nilable(RequestFailed))
        @queued_messages.pending(workflow_id: workflow_id).each do |row|
          begin
            result = @routing.route(inbox_id: row.inbox_id)
            @queued_messages.remove(id: row.id) if route_dispatched?(result)
          rescue ArgumentError, RequestFailed => error
            if error.is_a?(RequestFailed) && ![403, 404].include?(error.status)
              transient = error
              break
            end
            # Retain invalid sources for reconciliation; one revoked message
            # must not prevent other verified instructions from being released.
            @audit.record_once(event_key: "release:invalid:#{row.id}", action: "release_source_rejected",
                               details: Domains::Reviews::Dto::ReleaseRejectedAudit.new(workflow_id: workflow_id, inbox_id: row.inbox_id))
          end
        end
        @db[:followups].where(workflow_id: workflow_id, status: "queued").each do |row|
          job = @jobs.find_by_key(dispatch_key: "followup:#{row[:id]}")
          @jobs.requeue_blocked(id: job.id) if job
        end
        raise transient if transient
      end

      sig { params(result: Object).returns(T::Boolean) }
      private def route_dispatched?(result)
        result.is_a?(Hash) && (result.key?(:id) || result.key?("id"))
      end
    end
  end
end
