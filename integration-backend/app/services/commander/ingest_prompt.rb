# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    # Records a verified human prompt as a Commander request once per inbox
    # record: it reserves the Commander, writes the request token file,
    # queues commander.dispatch and posts the queued notice. Returns the request id.
    class IngestPrompt
      extend T::Sig

      Messaging = Domains::Messaging
      Outcome = T.type_alias { Kirei::Services::Result[String] }
      EXPIRY_SECONDS = 1800

      sig do
        params(source: Messaging::VerifyHumanSource, bootstrap: Sessions::BootstrapCommander, configuration: Domains::Workflows::Dto::RoleConfig,
               credentials: Adapters::Credentials::FileStore, requests: Domains::Commander::CommanderRequests, operations: Domains::Sessions::Operations,
               inbox: Messaging::Inbox, outbox: Messaging::Outbox, jobs: Platform::Jobs::Store, transaction: Platform::Transaction).void
      end
      def initialize(source:, bootstrap:, configuration:, credentials:, requests: Domains::Commander::CommanderRequests.new,
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

          commander = @bootstrap.call(configuration: @configuration)
          next commander if commander.failed?

          @transaction.call { ingest(inbox_id, verified.result, commander.result) }
        end
      end

      sig { params(inbox_id: String, delivery: Messaging::Dto::VerifiedDelivery, commander: String).returns(Outcome) }
      private def ingest(inbox_id, delivery, commander)
        @inbox.lock(id: inbox_id)
        existing = @requests.for_inbox(inbox_id: inbox_id)
        return Kirei::Services::Result.new(result: existing.id) if existing

        token = SecureRandom.hex(32)
        created = @requests.create(inbox_id: inbox_id, session_id: commander, credential_digest: Digest::SHA256.hexdigest(token),
                                   expires_at: Time.now + EXPIRY_SECONDS)
        return Kirei::Services::Result.new(errors: created.errors) if created.failed?

        id = created.result.id
        @credentials.write(name: "#{id}.request-token", token: token)
        @jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::CommanderDispatch, payload: Domains::Commander::Dto::CommanderDispatchJob.new(request_id: id),
                      dispatch_key: "commander:dispatch:#{id}")
        start = @operations.for_session(session_id: commander, kind: Domains::Sessions::Dto::OperationKind::Start)
        message = Messaging::Dto::OutgoingMessage.new(
          channel_id: delivery.channel_id,
          thread_id: delivery.thread_id,
          bot: Messaging::Dto::Bot::Commander,
          role: Messaging::Dto::SpeakerRole::Commander,
          body: "Request #{id} queued for Commander; delivery pending. Session #{commander}, start operation #{start&.id}.",
          key: "commander:queued:#{id}"
        )
        Platform::Unwrap.call(@outbox.enqueue(message: message))
        Kirei::Services::Result.new(result: id)
      end
    end
  end
end
