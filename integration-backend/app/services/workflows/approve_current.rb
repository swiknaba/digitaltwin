# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Handles workflow.approve: a contextual `@agent approve` by default in the workflow
    # thread approves the artifact of the current human approval gate at the
    # version the router saw, then advances the workflow.
    class ApproveCurrent
      extend T::Sig
      include Platform::Jobs::Handler

      Code = Dto::ErrorCode
      Gate = Domains::Workflows::Dto::Gate
      Outcome = T.type_alias { Kirei::Services::Result[Domains::Workflows::Dto::WorkflowView] }

      sig do
        params(source: Domains::Messaging::VerifyHumanSource, approvals: Commander::RecordApproval, advance: AdvanceApproval,
               catalog: Domains::Workflows::Catalog).void
      end
      def initialize(source:, approvals:, advance:, catalog: Domains::Workflows::Catalog.new)
        @source = source
        @approvals = approvals
        @advance = advance
        @catalog = catalog
      end

      # Failures raise, so the worker keeps today's retry path.
      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          Platform::Unwrap.call(approve(Domains::Commander::Dto::InboxDispatchJob.from_hash(job.payload, true)))
          Platform::Jobs::Dto::Decision.complete
        end
      end

      sig { params(payload: Domains::Commander::Dto::InboxDispatchJob).returns(Outcome) }
      private def approve(payload)
        verified = @source.call(inbox_id: payload.inbox_id)
        return Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

        delivery = verified.result
        workflow_id = payload.workflow_id
        return malformed unless workflow_id

        workflow = @catalog.find(id: workflow_id)
        same_thread = workflow && delivery.channel_id == workflow.channel_id && delivery.thread_id == workflow.thread_id
        return failure(Code::SourceMismatch, "Approval source/workflow mismatch") unless workflow && same_thread

        expected_version = payload.expected_version
        return malformed unless expected_version
        return failure(Code::SourceMismatch, "Approval source/workflow mismatch") unless workflow.version == expected_version

        gate = [Gate::Spec, Gate::Plan].find { |candidate| candidate.human_approval_phase == workflow.phase }
        return failure(Code::ApprovalPhaseMismatch, "Approval phase mismatch") unless gate

        ref = workflow.artifacts.fetch(gate)
        return failure(Code::InvalidArtifact, "Invalid workflow artifact") unless ref

        recorded = @approvals.call(inbox_id: payload.inbox_id, workflow_id: workflow.id, gate: gate, commit: ref.commit)
        return Kirei::Services::Result.new(errors: recorded.errors) if recorded.failed?

        @advance.call(workflow_id: workflow.id, gate: gate)
      end

      sig { returns(Outcome) }
      private def malformed = failure(Code::MalformedJob, "Commander job is malformed")

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
