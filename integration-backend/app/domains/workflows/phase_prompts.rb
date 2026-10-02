# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    # Queues the Writer prompt for one workflow version. The dispatch key makes
    # each version's prompt idempotent.
    class PhasePrompts
      extend T::Sig

      Kind = Platform::Jobs::Dto::JobKind

      sig { params(jobs: Platform::Jobs::Store).void }
      def initialize(jobs: Platform::Jobs::Store.new)
        @jobs = jobs
      end

      sig { params(workflow_id: String, version: Integer).returns(String) }
      def enqueue(workflow_id:, version:)
        @jobs.enqueue(kind: Kind::WorkflowPhasePrompt, payload: Dto::PhasePromptJob.new(workflow_id: workflow_id, version: version),
                      dispatch_key: "workflow:phase:#{workflow_id}:#{version}")
      end

      sig { params(workflow_id: String).returns(T::Boolean) }
      def unstarted?(workflow_id:) = @jobs.unstarted?(kind: Kind::WorkflowPhasePrompt, field: "workflow_id", value: workflow_id)
    end
  end
end
