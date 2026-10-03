# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    # Queues one review.release job per workflow version; ReleaseQueued runs it.
    class QueueRelease
      extend T::Sig

      sig { params(jobs: Platform::Jobs::Store).void }
      def initialize(jobs: Platform::Jobs::Store.new)
        @jobs = jobs
      end

      sig { params(workflow_id: String, version: Integer).returns(String) }
      def call(workflow_id:, version:)
        @jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::ReviewRelease, payload: Domains::Reviews::Dto::ReviewReleaseJob.new(workflow_id: workflow_id),
                      dispatch_key: "review:release:#{workflow_id}:#{version}")
      end
    end
  end
end
