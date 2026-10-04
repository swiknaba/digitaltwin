# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    # Handles workflow.prompt: records an exact approve command, or routes the
    # message as a follow-up (with the human's route selection, if any).
    class HandleWorkflowPrompt
      extend T::Sig
      include Platform::Jobs::Handler

      Decision = Platform::Jobs::Dto::Decision
      Messaging = Domains::Messaging

      sig do
        params(route: RouteFollowup, approvals: RecordApproval, handle: String, worker_handle: String, inbox: Messaging::Inbox,
               outbox: Messaging::Outbox, parser: Commands::Parser).void
      end
      def initialize(route:, approvals:, handle:, worker_handle:, inbox: Messaging::Inbox.new, outbox: Messaging::Outbox.new,
                     parser: Commands::Parser.new)
        @route = route
        @approvals = approvals
        @inbox = inbox
        @outbox = outbox
        @parser = parser
        @handle = handle
        @worker_handle = worker_handle
      end

      # Failures raise, so the worker keeps today's retry path.
      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          id = Domains::Commander::Dto::InboxDispatchJob.from_hash(job.payload, true).inbox_id
          source = T.must(@inbox.find(id: id))
          command = @parser.call(body: source.verified_delivery.body, agent_handle: @handle, worker_handle: @worker_handle)
          if command.is_a?(Commands::Dto::Approve)
            gate = command.gate.serialize
            Platform::Unwrap.call(@approvals.call(inbox_id: id, workflow_id: command.workflow_id, gate: Domains::Workflows::Dto::Gate.deserialize(gate), commit: command.commit))
            notify(source, "#{gate} approval recorded for #{command.workflow_id} at #{command.commit}.", "commander:#{id}:approval")
            next Decision.complete
          end
          selection = command.is_a?(Commands::Dto::Route) ? command.workflow_id : nil
          Platform::Unwrap.call(@route.call(inbox_id: id, selection: selection))
          Decision.complete
        end
      end

      sig { params(source: Messaging::Dto::InboxRecord, body: String, key: String).void }
      private def notify(source, body, key)
        message = Messaging::Dto::OutgoingMessage.new(channel_id: source.channel_id, thread_id: source.thread_id, bot: Messaging::Dto::Bot::Agent,
                                                      role: Messaging::Dto::SpeakerRole::Commander, body: body, key: key)
        Platform::Unwrap.call(@outbox.enqueue(message: message))
      end
    end
  end
end
