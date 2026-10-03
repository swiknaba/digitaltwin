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

      sig do
        params(route: Master::RouteFollowup, followups: Domains::Commander::Followups, catalog: Domains::Workflows::Catalog,
               queued_messages: Domains::Workflows::QueuedMessages, jobs: Platform::Jobs::Store, audit: Platform::Audit::Log).void
      end
      def initialize(route:, followups: Domains::Commander::Followups.new, catalog: Domains::Workflows::Catalog.new,
                     queued_messages: Domains::Workflows::QueuedMessages.new, jobs: Platform::Jobs::Store.new, audit: Platform::Audit::Log.new)
        @route = route
        @followups = followups
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
            result = @route.call(inbox_id: row.inbox_id)
            @queued_messages.remove(id: row.id) if result.success? && route_dispatched?(result.result)
            reject(workflow_id, row) if result.failed?
          rescue ArgumentError, RequestFailed => error
            if error.is_a?(RequestFailed) && ![403, 404].include?(error.status)
              transient = error
              break
            end
            reject(workflow_id, row)
          end
        end
        @followups.queued_ids(workflow_id: workflow_id).each do |id|
          job = @jobs.find_by_key(dispatch_key: "followup:#{id}")
          @jobs.requeue_blocked(id: job.id) if job
        end
        raise transient if transient
      end

      # Retain invalid sources for reconciliation; one revoked message must
      # not prevent other verified instructions from being released.
      sig { params(workflow_id: String, row: Domains::Workflows::Dto::QueuedMessageView).void }
      private def reject(workflow_id, row)
        @audit.record_once(event_key: "release:invalid:#{row.id}", action: "release_source_rejected",
                           details: Domains::Reviews::Dto::ReleaseRejectedAudit.new(workflow_id: workflow_id, inbox_id: row.inbox_id))
      end

      # A clarification leaves the message queued.
      sig { params(outcome: Master::Dto::RouteOutcome).returns(T::Boolean) }
      private def route_dispatched?(outcome) = !outcome.followup.nil?
    end
  end
end
