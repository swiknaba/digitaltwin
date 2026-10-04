# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    # Durable session start and stop operations, and the session state that
    # their runtime effects prove. Callers hold the scope's Platform::Lock
    # (workflow id, or "commander"). Each session has at most one operation
    # per kind; the dispatch keys are "session:<kind>:<session id>".
    class Operations
      extend T::Sig

      Outcome = T.type_alias { Kirei::Services::Result[Dto::OperationView] }
      Kind = Platform::Jobs::Dto::JobKind
      UNSETTLED_STATES = T.let(Dto::OperationState.values.select(&:unsettled?).map(&:serialize).freeze, T::Array[String])

      sig { params(registry: Registry, jobs: Platform::Jobs::Store).void }
      def initialize(registry: Registry.new, jobs: Platform::Jobs::Store.new)
        @registry = registry
        @jobs = jobs
      end

      # Creates the inactive session and its start operation, and queues the
      # start job, in one transaction. A pending start in the scope is returned
      # instead, so a replay reserves nothing new.
      sig do
        params(session_id: String, workflow_id: T.nilable(String), role: Dto::SessionRole, configuration: Workflows::Dto::RoleConfig,
               credential_digest: String).returns(Outcome)
      end
      def reserve(session_id:, workflow_id:, role:, configuration:, credential_digest:)
        Entities::RuntimeSession.db.transaction do
          next failure(Dto::ErrorCode::SessionActive, "Session already active") if active_in_scope?(workflow_id, role)

          pending = @registry.pending_start(workflow_id: workflow_id, role: role)
          next Kirei::Services::Result.new(result: T.must(for_session(session_id: pending.id, kind: Dto::OperationKind::Start))) if pending
          next failure(Dto::ErrorCode::IncompleteConfiguration, "Incomplete role configuration") unless ConfigurationPolicy.complete?(configuration)

          generation = @registry.latest_generation(workflow_id: workflow_id, role: role) + 1
          runtime_alias = "digitaltwin-#{session_id}"
          unless /\A[a-z][a-z0-9_-]{0,31}\z/.match?(runtime_alias)
            runtime_alias = "digitaltwin-#{Digest::SHA256.hexdigest(session_id).slice(0, 20)}"
          end
          Entities::RuntimeSession.create(id: session_id, workflow_id: workflow_id, role: role.serialize, generation: generation, pane_id: "pending:#{session_id}",
                                          alias: runtime_alias, configuration: configuration.serialize, credential_digest: credential_digest,
                                          credential_expires_at: Time.now + 3600, active: false)
          operation = create(session_id, Dto::OperationKind::Start)
          @jobs.enqueue(kind: Kind::SessionStart, payload: Dto::SessionOperationJob.new(operation_id: operation.id), dispatch_key: "session:start:#{session_id}")
          Kirei::Services::Result.new(result: operation)
        end
      end

      # Queues one stop per active workflow session that has no stop yet.
      sig { params(workflow_id: String).void }
      def queue_stops(workflow_id:)
        Entities::SessionOperation.db.transaction do
          @registry.active(workflow_id: workflow_id, role: nil).each do |session|
            next if for_session(session_id: session.id, kind: Dto::OperationKind::Stop)

            operation = create(session.id, Dto::OperationKind::Stop)
            @jobs.enqueue(kind: Kind::SessionStop, payload: Dto::SessionOperationJob.new(operation_id: operation.id), dispatch_key: "session:stop:#{session.id}")
          end
        end
      end

      sig { params(id: String).returns(T.nilable(Dto::OperationView)) }
      def find(id:) = Records.operations(Entities::SessionOperation.query.where(id: id)).first

      sig { params(session_id: String, kind: Dto::OperationKind).returns(T.nilable(Dto::OperationView)) }
      def for_session(session_id:, kind:)
        Records.operations(Entities::SessionOperation.query.where(session_id: session_id, kind: kind.serialize)).first
      end

      # A nil reason keeps the stored reason.
      sig { params(id: String, state: Dto::OperationState, reason: T.nilable(String)).void }
      def mark(id:, state:, reason: nil)
        changes = { state: state.serialize }
        changes[:reason] = reason if reason
        Entities::SessionOperation.query.where(id: id).update(changes)
      end

      # True when a session of these workflows has a sending or uncertain operation.
      sig { params(workflow_ids: T::Array[String]).returns(T::Boolean) }
      def unsettled_in_workflows?(workflow_ids:)
        sessions = Entities::RuntimeSession.query.where(workflow_id: workflow_ids).select(:id)
        !Entities::SessionOperation.query.where(session_id: sessions, state: UNSETTLED_STATES).empty?
      end

      # Binds the created Herdr workspace before the agent starts, so an
      # uncertain start keeps its recorded pane.
      sig { params(session_id: String, pane_id: String, workspace_id: String).void }
      def record_workspace(session_id:, pane_id:, workspace_id:)
        Entities::RuntimeSession.query.where(id: session_id).update(pane_id: pane_id, workspace_id: workspace_id)
      end

      sig { params(session_id: String, identity: Dto::RuntimeIdentity, state: Dto::SessionState).void }
      def activate(session_id:, identity:, state:)
        update_session(session_id, { active: true, runtime_identity: identity.serialize, state: state.serialize, last_verified_at: Time.now })
      end

      # Activation from human-verified reconciliation evidence. It also binds
      # the pane and extends the credential.
      sig { params(session_id: String, pane_id: String, identity: Dto::RuntimeIdentity, state: Dto::SessionState, credential_expires_at: Time).void }
      def activate_reconciled(session_id:, pane_id:, identity:, state:, credential_expires_at:)
        update_session(session_id, { pane_id: pane_id, active: true, runtime_identity: identity.serialize, state: state.serialize,
                                     credential_expires_at: credential_expires_at, last_verified_at: Time.now })
      end

      sig { params(session_id: String).void }
      def deactivate(session_id:)
        Entities::RuntimeSession.query.where(id: session_id).update(active: false, state: Dto::SessionState::Done.serialize)
      end

      sig { params(workflow_id: T.nilable(String), role: Dto::SessionRole).returns(T::Boolean) }
      private def active_in_scope?(workflow_id, role)
        return !@registry.active_commander.nil? unless workflow_id

        @registry.active(workflow_id: workflow_id, role: role).any?
      end

      sig { params(session_id: String, kind: Dto::OperationKind).returns(Dto::OperationView) }
      private def create(session_id, kind)
        id = SecureRandom.uuid
        Entities::SessionOperation.query.insert(id: id, session_id: session_id, kind: kind.serialize)
        T.must(find(id: id))
      end

      sig { params(session_id: String, changes: T::Hash[Symbol, T.any(String, T::Boolean, Time, T::Hash[String, String])]).void }
      private def update_session(session_id, changes)
        Entities::RuntimeSession.wrap_jsonb_non_primivitives!(changes)
        Entities::RuntimeSession.query.where(id: session_id).update(changes)
      end

      sig { params(code: Dto::ErrorCode, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
