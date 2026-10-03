# typed: strict
# frozen_string_literal: true

module Services
  module Master
    # Records a verified human prompt as a Master request once per inbox
    # record: it reserves the Controller, writes the request token file,
    # queues master.dispatch and posts the queued notice. Returns the request id.
    class IngestPrompt
      extend T::Sig

      Messaging = Domains::Messaging
      Outcome = T.type_alias { Kirei::Services::Result[String] }
      EXPIRY_SECONDS = 1800

      sig do
        params(source: Messaging::VerifyHumanSource, bootstrap: Sessions::BootstrapController, configuration: Domains::Workflows::Dto::RoleConfig,
               credentials: Adapters::Credentials::FileStore, requests: Domains::Commander::MasterRequests, operations: Domains::Sessions::Operations,
               inbox: Messaging::Inbox, outbox: Messaging::Outbox, jobs: Platform::Jobs::Store, transaction: Platform::Transaction).void
      end
      def initialize(source:, bootstrap:, configuration:, credentials:, requests: Domains::Commander::MasterRequests.new,
                     operations: Domains::Sessions::Operations.new, inbox: Messaging::Inbox.new, outbox: Messaging::Outbox.new,
                     jobs: Platform::Jobs::Store.new, transaction: Platform::Transaction.new)
        @source = source
        @bootstrap = bootstrap
        @configuration = configuration
        @credentials = credentials
        @requests = requests
        @operations = operations
        @inbox = inbox
        @outbox = outbox
        @jobs = jobs
        @transaction = transaction
      end

      sig { params(inbox_id: String).returns(Outcome) }
      def call(inbox_id:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          verified = @source.call(inbox_id: inbox_id)
          next Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

          controller = @bootstrap.call(configuration: @configuration)
          next controller if controller.failed?

          @transaction.call { ingest(inbox_id, verified.result, controller.result) }
        end
      end

      sig { params(inbox_id: String, delivery: Messaging::Dto::VerifiedDelivery, controller: String).returns(Outcome) }
      private def ingest(inbox_id, delivery, controller)
        @inbox.lock(id: inbox_id)
        existing = @requests.for_inbox(inbox_id: inbox_id)
        return Kirei::Services::Result.new(result: existing.id) if existing

        token = SecureRandom.hex(32)
        created = @requests.create(inbox_id: inbox_id, session_id: controller, credential_digest: Digest::SHA256.hexdigest(token),
                                   expires_at: Time.now + EXPIRY_SECONDS)
        return Kirei::Services::Result.new(errors: created.errors) if created.failed?

        id = created.result.id
        @credentials.write(name: "#{id}.request-token", token: token)
        @jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::MasterDispatch, payload: Domains::Commander::Dto::MasterDispatchJob.new(request_id: id),
                      dispatch_key: "master:dispatch:#{id}")
        start = @operations.for_session(session_id: controller, kind: Domains::Sessions::Dto::OperationKind::Start)
        message = Messaging::Dto::OutgoingMessage.new(
          channel_id: delivery.channel_id,
          thread_id: delivery.thread_id,
          bot: Messaging::Dto::Bot::Agent,
          role: Messaging::Dto::SpeakerRole::Controller,
          body: "Request #{id} queued for Master; delivery pending. Session #{controller}, start operation #{start&.id}.",
          key: "master:queued:#{id}"
        )
        Platform::Unwrap.call(@outbox.enqueue(message: message))
        Kirei::Services::Result.new(result: id)
      end
    end
  end
end
