# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    # Handles session.start and session.stop: runs the queued operation's
    # Herdr effect once. A start creates the workspace with the callback
    # environment, starts the agent and binds its proven conversation. A stop
    # closes only the recorded, settled conversation. Any failure after the
    # effect may have begun leaves the operation uncertain; it is never
    # repeated, and ReconcileOperation settles it from human-verified evidence.
    class ExecuteOperation
      extend T::Sig
      include Platform::Jobs::Handler

      Decision = Platform::Jobs::Dto::Decision
      Sessions = Domains::Sessions
      State = Sessions::Dto::OperationState
      Kind = Sessions::Dto::OperationKind
      Phase = Domains::Workflows::Dto::Phase
      Workflow = Domains::Workflows::Dto::WorkflowView
      Identity = Adapters::Herdr::ConversationIdentity

      sig do
        params(herdr: Adapters::Herdr::Client, source: Domains::Messaging::VerifyHumanSource, credentials: Adapters::Credentials::FileStore, callback_url: String,
               policy: Domains::Workflows::Policy, registry: Sessions::Registry, operations: Sessions::Operations, catalog: Domains::Workflows::Catalog,
               complete: CompleteOperation, lock: Platform::Lock).void
      end
      def initialize(herdr:, source:, credentials:, callback_url:, policy: Domains::Workflows::Policy.new, registry: Sessions::Registry.new,
                     operations: Sessions::Operations.new, catalog: Domains::Workflows::Catalog.new, complete: CompleteOperation.new, lock: Platform::Lock.new)
        @herdr = herdr
        @source = source
        @credentials = credentials
        @url = callback_url
        @policy = policy
        @registry = registry
        @operations = operations
        @catalog = catalog
        @complete = complete
        @lock = lock
      end

      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          operation_id = Sessions::Dto::SessionOperationJob.from_hash(job.payload, true).operation_id
          state = execute(operation_id, -> { job.lease.begin_effect })
          if state == State::Queued && @policy.dispatch_allowed?
            Decision.defer("Session start waits for phase")
          elsif state != State::Complete
            Decision.block("Session #{state.serialize}; evidence/reconciliation required")
          else
            Decision.complete
          end
        end
      end

      sig { params(operation_id: String, before_effect: T.proc.returns(T::Boolean)).returns(State) }
      private def execute(operation_id, before_effect)
        operation = @operations.find(id: operation_id) or raise ArgumentError, "Missing session operation"
        session = T.must(@registry.find(id: operation.session_id))
        @lock.call(key: session.workflow_id || "commander") do
          operation = T.must(@operations.find(id: operation_id))
          next operation.state unless operation.state == State::Queued
          next State::Queued unless @policy.dispatch_allowed?

          workflow = workflow_for(session.workflow_id)
          Platform::Unwrap.call(@source.call(inbox_id: source_inbox_id(workflow), destination: workflow.channel_id)) if workflow
          next State::Queued if operation.kind == Kind::Start && workflow && closed_for_start?(workflow)

          @operations.mark(id: operation_id, state: State::Sending)
          begin
            raise IOError, "Dispatch lease lost" unless before_effect.call

            operation.kind == Kind::Start ? start(operation, session, workflow) : stop(operation, session, workflow)
            State::Complete
          rescue StandardError
            @operations.mark(id: operation_id, state: State::Uncertain, reason: "Runtime effect requires reconciliation; do not repeat")
            State::Uncertain
          end
        end
      end

      sig { params(operation: Sessions::Dto::OperationView, session: Sessions::Dto::SessionView, workflow: T.nilable(Workflow)).void }
      private def start(operation, session, workflow)
        env = { "DIGITALTWIN_SESSION_TOKEN_FILE" => @credentials.path(name: "#{session.id}.token"), "DIGITALTWIN_SESSION_GENERATION" => session.generation.to_s,
                "DIGITALTWIN_CALLBACK_URL" => @url, "DIGITALTWIN_COMMANDER_REQUEST_TOKEN_FILE" => @credentials.path(name: "#{session.id}.request-token") }
        created = @herdr.create_workspace(cwd: workflow&.worktree_path, label: session.alias, env: env)
        @operations.record_workspace(session_id: session.id, pane_id: created.root_pane_id, workspace_id: created.workspace_id)
        launch = Adapters::Herdr::Dto::LaunchSpec.new(cli: session.configuration.cli, launch_args: session.configuration.launch_args)
        live = @herdr.start(pane_id: created.root_pane_id, name: session.alias, launch: launch)
        identity = live.agent_session
        raise IOError, "Unproved conversation identity" unless identity && Identity.proven?(identity)

        Platform::Transaction.new.call do
          @operations.activate(session_id: session.id, identity: Identity.from_live(identity), state: Sessions::Dto::SessionState.deserialize(live.agent_status.serialize))
          @complete.call(operation: operation, session: session, workflow: workflow)
        end
      end

      # Stops only the recorded conversation; a session without a stored
      # identity matches only a pane that reports none.
      sig { params(operation: Sessions::Dto::OperationView, session: Sessions::Dto::SessionView, workflow: T.nilable(Workflow)).void }
      private def stop(operation, session, workflow)
        live = @herdr.pane(session.pane_id)
        raise IOError, "Uncertain or replaced session" unless live.agent_session&.serialize == session.runtime_identity&.serialize && live.agent_status.settled?

        @herdr.close(pane_id: session.pane_id)
        Platform::Transaction.new.call do
          @operations.deactivate(session_id: session.id)
          @complete.call(operation: operation, session: session, workflow: workflow)
        end
        @credentials.delete(name: "#{session.id}.token")
      end

      sig { params(workflow: Workflow).returns(T::Boolean) }
      private def closed_for_start?(workflow)
        workflow.phase == Phase::Paused || !workflow.archived_at.nil? || workflow.phase.terminal?
      end

      sig { params(workflow_id: T.nilable(String)).returns(T.nilable(Workflow)) }
      private def workflow_for(workflow_id) = workflow_id && @catalog.find(id: workflow_id)

      sig { params(workflow: Workflow).returns(String) }
      private def source_inbox_id(workflow)
        workflow.source_inbox_id or raise ArgumentError, "Missing verified source"
      end
    end
  end
end
