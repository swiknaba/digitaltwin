# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    # Reserves the Controller (Master) session. Only operator-configured
    # bootstrap calls this; it is never an MCP tool for Worker/Reviewer or
    # accepted from a model-supplied role. An active Controller is returned
    # (and its renewal queued when it expires within 5 minutes); a pending
    # start is returned as is. Returns the session id.
    class BootstrapController
      extend T::Sig

      Code = Dto::ErrorCode
      Role = Domains::Sessions::Dto::SessionRole
      Outcome = T.type_alias { Kirei::Services::Result[String] }

      sig do
        params(credentials: Adapters::Credentials::FileStore, registry: Domains::Sessions::Registry, operations: Domains::Sessions::Operations,
               renewals: Domains::Sessions::Renewals, lock: Platform::Lock).void
      end
      def initialize(credentials:, registry: Domains::Sessions::Registry.new, operations: Domains::Sessions::Operations.new,
                     renewals: Domains::Sessions::Renewals.new, lock: Platform::Lock.new)
        @credentials = credentials
        @registry = registry
        @operations = operations
        @renewals = renewals
        @lock = lock
      end

      sig { params(configuration: Domains::Workflows::Dto::RoleConfig).returns(Outcome) }
      def call(configuration:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          @lock.call(key: "controller") { bootstrap(configuration) }
        end
      end

      sig { params(configuration: Domains::Workflows::Dto::RoleConfig).returns(Outcome) }
      private def bootstrap(configuration)
        existing = @registry.active_controller
        if existing
          @renewals.schedule(session: existing) if existing.credential_expires_at <= Time.now + 300
          return Kirei::Services::Result.new(result: existing.id)
        end

        pending = @registry.pending_start(workflow_id: nil, role: Role::Controller)
        return Kirei::Services::Result.new(result: pending.id) if pending
        unless Domains::Sessions::ConfigurationPolicy.complete?(configuration)
          return Kirei::Services::Result.new(errors: Platform::Failure.call(code: Code::IncompleteConfiguration, detail: "Incomplete role configuration"))
        end

        id = @registry.next_id
        token = SecureRandom.hex(32)
        @credentials.write(name: "#{id}.token", token: token)
        reserved = @operations.reserve(session_id: id, workflow_id: nil, role: Role::Controller, configuration: configuration,
                                       credential_digest: Digest::SHA256.hexdigest(token))
        return Kirei::Services::Result.new(errors: reserved.errors) if reserved.failed?

        Kirei::Services::Result.new(result: id)
      end
    end
  end
end
