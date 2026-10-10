# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    # Reserves the Writer or Reviewer session of a workflow from its verified
    # source: writes the session credential, records the session and its
    # queued start, and posts the "reserved" notice. An active session is
    # returned (and its renewal queued when it expires within 5 minutes); a
    # pending start is returned as is. Returns the session id.
    class ReserveSession
      extend T::Sig

      Code = Dto::ErrorCode
      Role = Domains::Sessions::Dto::SessionRole
      Workflow = Domains::Workflows::Dto::WorkflowView
      Messaging = Domains::Messaging
      Outcome = T.type_alias { Kirei::Services::Result[String] }

      sig do
        params(source: Messaging::VerifyHumanSource, credentials: Adapters::Credentials::FileStore, registry: Domains::Sessions::Registry,
               operations: Domains::Sessions::Operations, renewals: Domains::Sessions::Renewals, catalog: Domains::Workflows::Catalog,
               outbox: Messaging::Outbox, lock: Platform::Lock).void
      end
      def initialize(source:, credentials:, registry: Domains::Sessions::Registry.new, operations: Domains::Sessions::Operations.new,
                     renewals: Domains::Sessions::Renewals.new, catalog: Domains::Workflows::Catalog.new, outbox: Messaging::Outbox.new, lock: Platform::Lock.new)
        @source = source
        @credentials = credentials
        @registry = registry
        @operations = operations
        @renewals = renewals
        @catalog = catalog
        @outbox = outbox
        @lock = lock
      end

      sig { params(workflow_id: String, role: Role).returns(Outcome) }
      def call(workflow_id:, role:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          next failure(Code::WorkflowRoleRequired, "Workflow role required") unless [Role::Writer, Role::Reviewer].include?(role)

          workflow = @catalog.find(id: workflow_id)
          next failure(Code::MissingWorkflow, "Missing workflow") unless workflow

          inbox_id = workflow.source_inbox_id
          next failure(Code::MissingSource, "Missing verified source") unless inbox_id

          verified = @source.call(inbox_id: inbox_id, destination: workflow.channel_id)
          next Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

          @lock.call(key: workflow_id) { reserve(workflow, role) }
        end
      end

      sig { params(workflow: Workflow, role: Role).returns(Outcome) }
      private def reserve(workflow, role)
        existing = @registry.active(workflow_id: workflow.id, role: role).first
        if existing
          @renewals.schedule(session: existing) if existing.credential_expires_at <= Time.now + 300
          return Kirei::Services::Result.new(result: existing.id)
        end

        pending = @registry.pending_start(workflow_id: workflow.id, role: role)
        return Kirei::Services::Result.new(result: pending.id) if pending

        configuration = role == Role::Writer ? workflow.role_configurations.writer : workflow.role_configurations.reviewer
        return failure(Code::IncompleteConfiguration, "Incomplete role configuration") unless Domains::Sessions::ConfigurationPolicy.complete?(configuration)

        id = @registry.next_id
        token = SecureRandom.hex(32)
        @credentials.write(name: "#{id}.token", token: token)
        Platform::Transaction.new.call do
          reserved = Platform::Unwrap.call(@operations.reserve(session_id: id, workflow_id: workflow.id, role: role, configuration: configuration,
                                                               credential_digest: Digest::SHA256.hexdigest(token)))
          notify(workflow, role, id, reserved.id)
          Kirei::Services::Result.new(result: id)
        end
      end

      sig { params(workflow: Workflow, role: Role, session_id: String, operation_id: String).void }
      private def notify(workflow, role, session_id, operation_id)
        message = Messaging::Dto::OutgoingMessage.new(
          channel_id: workflow.channel_id,
          thread_id: workflow.thread_id,
          bot: Messaging::Dto::Bot::Agent,
          role: Messaging::Dto::SpeakerRole.deserialize(role.serialize),
          body: "#{role.serialize.capitalize} session #{session_id} reserved; start operation #{operation_id} is queued, not started.",
          key: "session:reserved:#{session_id}"
        )
        Platform::Unwrap.call(@outbox.enqueue(message: message))
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
