# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    # Handles review.callback: applies a callback that QueueCallback authenticated.
    class ApplyCallback
      extend T::Sig
      include Platform::Jobs::Handler

      Decision = Platform::Jobs::Dto::Decision

      sig { params(artifact_ready: ArtifactReady, review_finished: ReviewFinished).void }
      def initialize(artifact_ready:, review_finished:)
        @artifact_ready = artifact_ready
        @review_finished = review_finished
      end

      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          payload = Domains::Reviews::Dto::ReviewCallbackJob.from_hash(job.payload, true)
          caller = Dto::QueuedSession.new(session_id: payload.session_id)
          if payload.action == "artifact"
            @artifact_ready.call(caller: caller, generation: payload.generation, kind: required(payload.kind), commit: payload.commit)
          else
            @review_finished.call(caller: caller, generation: payload.generation, review_commit: payload.commit, verdict: required(payload.verdict))
          end
          Decision.complete
        end
      end

      sig { params(value: T.nilable(String)).returns(String) }
      private def required(value)
        raise ArgumentError, "Controller job is malformed" unless value

        value
      end
    end
  end
end
