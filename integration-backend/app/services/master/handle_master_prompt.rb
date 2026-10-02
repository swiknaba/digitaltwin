# typed: strict
# frozen_string_literal: true

module Services
  module Master
    # Handles master.prompt: runs an exact recovery command before model
    # interpretation, hands other prompts to the configured Master, and
    # otherwise treats the message as a workflow prompt.
    class HandleMasterPrompt
      extend T::Sig
      include Platform::Jobs::Handler

      Decision = Platform::Jobs::Dto::Decision
      Commands = ::Services::Commands::Dto

      sig do
        params(source: Domains::Messaging::VerifyHumanSource, reconcile_start: Workflows::ReconcileStart, reconcile_operation: Sessions::ReconcileOperation,
               reconcile_followup: ReconcileFollowup, recover: T.nilable(Recover), ingest_prompt: T.nilable(IngestPrompt),
               handle_workflow_prompt: HandleWorkflowPrompt, advance_approval: Workflows::AdvanceApproval, agent_handle: String, worker_handle: String,
               parser: ::Services::Commands::Parser).void
      end
      def initialize(source:, reconcile_start:, reconcile_operation:, reconcile_followup:, recover:, ingest_prompt:, handle_workflow_prompt:,
                     advance_approval:, agent_handle:, worker_handle:, parser: ::Services::Commands::Parser.new)
        @source = source
        @reconcile_start = reconcile_start
        @reconcile_operation = reconcile_operation
        @reconcile_followup = reconcile_followup
        @recover = recover
        @ingest_prompt = ingest_prompt
        @handle_workflow_prompt = handle_workflow_prompt
        @advance_approval = advance_approval
        @agent_handle = agent_handle
        @worker_handle = worker_handle
        @parser = parser
      end

      # Failures raise, so the worker keeps today's retry path.
      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          id = Domains::Commander::Dto::InboxDispatchJob.from_hash(job.payload, true).inbox_id
          next Decision.complete if handled_directly?(id)

          @handle_workflow_prompt.call(job: job)
          # Exact approvals advance only through the coordinator's independent
          # revision/gate validation. Normal contextual prompts keep their session.
          approval = parse(id)
          if approval.is_a?(Commands::Approve)
            Platform::Unwrap.call(@advance_approval.call(workflow_id: approval.workflow_id, gate: Domains::Workflows::Dto::Gate.deserialize(approval.gate.serialize)))
          end
          Decision.complete
        end
      end

      # Returns true when a recovery command or the Master consumed the prompt.
      sig { params(id: String).returns(T::Boolean) }
      private def handled_directly?(id)
        command = parse(id)
        case command
        when Commands::RecoverStart
          Platform::Unwrap.call(@reconcile_start.call(request_id: command.request_id, inbox_id: id, thread_id: command.thread_id))
          true
        when Commands::RecoverSession
          Platform::Unwrap.call(@reconcile_operation.call(operation_id: command.operation_id, inbox_id: id, pane_id: command.pane_id))
          true
        when Commands::RecoverFollowup
          Platform::Unwrap.call(@reconcile_followup.call(id: command.followup_id, inbox_id: id, outcome: command.outcome))
          true
        when Commands::RecoverMaster
          recover = @recover
          raise ArgumentError, "Master not configured" unless recover

          Platform::Unwrap.call(recover.call(request_id: command.request_id, inbox_id: id))
          true
        when Commands::Approve, Commands::Route, Commands::MalformedDirective
          false
        when Commands::WorkerCommand, NilClass
          ingest = @ingest_prompt
          return false unless ingest

          Platform::Unwrap.call(ingest.call(inbox_id: id))
          true
        else
          T.absurd(command)
        end
      end

      sig { params(inbox_id: String).returns(T.nilable(Commands::Command)) }
      private def parse(inbox_id)
        body = Platform::Unwrap.call(@source.call(inbox_id: inbox_id)).body
        @parser.call(body: body, agent_handle: @agent_handle, worker_handle: @worker_handle)
      end
    end
  end
end
