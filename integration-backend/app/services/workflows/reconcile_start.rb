# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Settles an uncertain start thread from the original human's exact
    # `recover-start` command and the bot-authored root post. The thread is
    # never posted again; provisioning continues with a new job.
    class ReconcileStart
      extend T::Sig

      Code = Dto::ErrorCode
      State = Domains::Workflows::Dto::RequestState
      Messaging = Domains::Messaging
      Jobs = Platform::Jobs
      Outcome = T.type_alias { Kirei::Services::Result[State] }

      sig do
        params(source: Messaging::VerifyHumanSource, api: Adapters::Mattermost::Api, bot_id: String, agent_handle: String, directory: Domains::Projects::Directory,
               requests: Domains::Workflows::Requests, inbox: Messaging::Inbox, outbox: Messaging::Outbox, audit: Platform::Audit::Log,
               jobs: Jobs::Store).void
      end
      def initialize(source:, api:, bot_id:, agent_handle:, directory: Domains::Projects::Directory.new, requests: Domains::Workflows::Requests.new,
                     inbox: Messaging::Inbox.new, outbox: Messaging::Outbox.new, audit: Platform::Audit::Log.new, jobs: Jobs::Store.new)
        @source = source
        @api = api
        @bot = bot_id
        @thread_bot = T.let(VerifyThreadBot.new(api: api, bot_id: bot_id), VerifyThreadBot)
        @directory = directory
        @requests = requests
        @inbox = inbox
        @outbox = outbox
        @audit = audit
        @jobs = jobs
        @agent = agent_handle
      end

      sig { params(request_id: String, inbox_id: String, thread_id: String).returns(Outcome) }
      def call(request_id:, inbox_id:, thread_id:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          next failure(Code::InvalidThread, "Invalid thread") unless thread_id.match?(/\A[a-z0-9]{26}\z/)

          Platform::Lock.new.call(key: "provision:#{request_id}") { reconcile(request_id, inbox_id, thread_id) }
        end
      end

      sig { params(id: String, inbox_id: String, thread_id: String).returns(Outcome) }
      private def reconcile(id, inbox_id, thread_id)
        request = @requests.find(id: id)
        return failure(Code::MissingRequest, "Unknown start request") unless request

        project = @directory.find(id: request.project_id)
        return failure(Code::UnknownProject, "Unknown project") unless project

        verified = @source.call(inbox_id: inbox_id, destination: project.channel_id)
        return Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

        delivery = verified.result
        original = T.must(@inbox.find(id: request.inbox_id))
        unless delivery.actor.user_id == original.user_id && delivery.body == "@#{@agent} recover-start #{id} #{thread_id}"
          return failure(Code::RecoveryNotAuthorized, "Exact original-human thread recovery required")
        end

        key = "workflow:recovery:#{id}"
        receipt = @audit.find(event_key: key)
        if receipt
          return failure(Code::RecoveryThreadChanged, "Recovery thread changed") unless Domains::Workflows::Dto::ThreadRecoveryAudit.from_hash(receipt.details, true).thread_id == thread_id

          return success
        end
        return failure(Code::NotReconcilable, "Start does not require reconciliation") unless [State::Sending, State::Uncertain].include?(request.state)

        job = @jobs.find_by_key(dispatch_key: "workflow:provision:#{id}")
        lease_expires_at = job&.lease_expires_at
        return failure(Code::LeaseLive, "Creation lease still live") if job&.status == Jobs::Dto::JobStatus::Running && lease_expires_at && lease_expires_at > Time.now
        return failure(Code::UnprovedThread, "Unproved created thread") unless proved_thread?(request, project, thread_id)

        Platform::Transaction.new.call do
          @requests.record_thread(id: id, thread_id: thread_id)
          @jobs.close_reconciled(id: job.id) if job
          @jobs.enqueue(kind: Jobs::Dto::JobKind::WorkflowProvision, payload: Domains::Workflows::Dto::ProvisionJob.new(request_id: id),
                        dispatch_key: "workflow:provision:reconciled:#{id}:#{thread_id}")
          @audit.record(event_key: key, action: "verified_thread_reconciliation",
                        details: Domains::Workflows::Dto::ThreadRecoveryAudit.new(inbox_id: inbox_id, request_id: id, thread_id: thread_id))
          message = Messaging::Dto::OutgoingMessage.new(
            channel_id: delivery.channel_id, thread_id: delivery.thread_id, bot: Messaging::Dto::Bot::Agent, role: Messaging::Dto::SpeakerRole::Commander,
            body: "Start #{id} reconciled to verified thread #{thread_id}; continuation queued without recreating the thread.", key: key
          )
          # A failed notice raises and rolls back the reconciliation, as before.
          Platform::Unwrap.call(@outbox.enqueue(message: message))
        end
        success
      end

      sig { params(request: Domains::Workflows::Dto::RequestView, project: Domains::Projects::Dto::Project, thread_id: String).returns(T::Boolean) }
      private def proved_thread?(request, project, thread_id)
        valid = @thread_bot.call(channel_id: project.channel_id)
        post = @api.post(thread_id)
        valid &&= post.id == thread_id && post.channel_id == project.channel_id && post.root_id.to_s.empty? && post.delete_at.zero?
        valid && post.user_id == @bot && post.message == request.parameters.title && post.props["digitaltwin_workflow_request"] == request.id
      end

      sig { returns(Outcome) }
      private def success = Kirei::Services::Result.new(result: State::Queued)

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
