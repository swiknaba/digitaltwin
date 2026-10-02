# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    # Settles a sending or uncertain session operation from runtime evidence,
    # on the exact recover-session command of the session's original human.
    # A start is proven by the exact alias, cwd, CLI and settled conversation
    # in the named pane; a stop by the pane's authoritative absence. Nothing
    # is started or stopped again. The audit receipt makes a replay with the
    # same pane return "complete".
    class ReconcileOperation
      extend T::Sig

      Code = Dto::ErrorCode
      Sessions = Domains::Sessions
      Kind = Sessions::Dto::OperationKind
      Messaging = Domains::Messaging
      Workflow = Domains::Workflows::Dto::WorkflowView
      Identity = Adapters::Herdr::ConversationIdentity
      Outcome = T.type_alias { Kirei::Services::Result[String] }
      # The proven live pane of a start.
      Evidence = T.type_alias { Kirei::Services::Result[Adapters::Herdr::Dto::Pane] }

      sig do
        params(db: Sequel::Database, herdr: Adapters::Herdr::Client, source: Messaging::VerifyHumanSource, credentials: Adapters::Credentials::FileStore,
               registry: Sessions::Registry, operations: Sessions::Operations, catalog: Domains::Workflows::Catalog, complete: CompleteOperation,
               inbox: Messaging::Inbox, outbox: Messaging::Outbox, audit: Platform::Audit::Log, jobs: Platform::Jobs::Store, lock: Platform::Lock, handle: String).void
      end
      def initialize(db, herdr:, source:, credentials:, registry: Sessions::Registry.new, operations: Sessions::Operations.new, catalog: Domains::Workflows::Catalog.new,
                     complete: CompleteOperation.new, inbox: Messaging::Inbox.new, outbox: Messaging::Outbox.new, audit: Platform::Audit::Log.new,
                     jobs: Platform::Jobs::Store.new, lock: Platform::Lock.new, handle: ENV.fetch("AGENT_HANDLE", "agent"))
        # master_requests stays a raw table until Task 9.
        @db = db
        @herdr = herdr
        @source = source
        @credentials = credentials
        @registry = registry
        @operations = operations
        @catalog = catalog
        @complete = complete
        @inbox = inbox
        @outbox = outbox
        @audit = audit
        @jobs = jobs
        @lock = lock
        @handle = handle
      end

      sig { params(operation_id: String, inbox_id: String, pane_id: String).returns(Outcome) }
      def call(operation_id:, inbox_id:, pane_id:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          operation = @operations.find(id: operation_id)
          next failure(Code::UnknownOperation, "Unknown session operation") unless operation

          session = T.must(@registry.find(id: operation.session_id))
          workflow = session.workflow_id && @catalog.find(id: T.must(session.workflow_id))
          original = original_source(session, workflow)
          next failure(Code::RecoveryRejected, "Human source binding required") unless original

          verified = @source.call(inbox_id: inbox_id, destination: workflow ? workflow.channel_id : original.channel_id)
          next Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

          delivery = verified.result
          command = "@#{@handle} recover-session #{operation_id} #{pane_id}"
          unless delivery.actor.user_id == original.user_id && delivery.body == command
            next failure(Code::RecoveryRejected, "Exact original-human session recovery required")
          end

          @lock.call(key: workflow ? workflow.id : "controller") { reconcile(operation_id, session.id, workflow, inbox_id, pane_id, delivery) }
        end
      end

      sig do
        params(operation_id: String, session_id: String, workflow: T.nilable(Workflow), inbox_id: String, pane_id: String,
               delivery: Messaging::Dto::VerifiedDelivery).returns(Outcome)
      end
      private def reconcile(operation_id, session_id, workflow, inbox_id, pane_id, delivery)
        operation = T.must(@operations.find(id: operation_id))
        key = "session:recovery:#{operation_id}"
        receipt = @audit.find(event_key: key)
        if receipt
          return failure(Code::RecoveryRejected, "Recovery pane changed") unless Sessions::Dto::SessionRecoveryAudit.from_hash(receipt.details, true).pane_id == pane_id

          return Kirei::Services::Result.new(result: "complete")
        end
        return failure(Code::RecoveryRejected, "Operation not uncertain") unless operation.state.unsettled?

        session = T.must(@registry.find(id: session_id))
        unless @registry.latest_generation(workflow_id: session.workflow_id, role: session.role) == session.generation
          return failure(Code::RecoveryRejected, "Session generation replaced")
        end
        return failure(Code::RecoveryRejected, "Different recorded pane") unless session.pane_id.start_with?("pending:") || session.pane_id == pane_id

        job = @jobs.find_by_key(dispatch_key: "session:#{operation.kind.serialize}:#{session.id}")
        lease_expires_at = job&.lease_expires_at
        if job&.status == Platform::Jobs::Dto::JobStatus::Running && lease_expires_at && lease_expires_at > Time.now
          return failure(Code::OperationLeaseLive, "Operation lease still live")
        end

        live = nil
        if operation.kind == Kind::Start
          proven = prove_start(session, workflow, pane_id)
          return Kirei::Services::Result.new(errors: proven.errors) if proven.failed?

          live = proven.result
        else
          absent = prove_stop(session, pane_id)
          return absent if absent.failed?
        end

        Platform::Transaction.new.call do
          apply(session, pane_id, live)
          @complete.call(operation: operation, session: session, workflow: workflow && @catalog.find(id: workflow.id))
          @jobs.close_reconciled(id: job.id) if job
          record(operation, session, inbox_id, pane_id, delivery)
        end
        @credentials.delete(name: "#{session.id}.token") if operation.kind == Kind::Stop
        Kirei::Services::Result.new(result: "complete")
      end

      sig { params(session: Sessions::Dto::SessionView, workflow: T.nilable(Workflow), pane_id: String).returns(Evidence) }
      private def prove_start(session, workflow, pane_id)
        return evidence_failure("Workflow closed", Code::RecoveryRejected) if workflow && (workflow.archived_at || workflow.phase.terminal?)

        live = @herdr.pane(pane_id)
        identity = live.agent_session
        return evidence_failure("Unproved exact role conversation") unless identity && Identity.proven?(identity)

        cli = session.configuration.cli
        valid = live.name == session.alias && live.cwd == (workflow ? workflow.worktree_path : "/home/runtime") && live.agent == cli && identity.agent == cli
        valid &&= live.agent_status.settled? && live.interactive_ready == true && live.launch_pending == false
        return evidence_failure("Unproved exact role conversation") unless valid

        token = @credentials.read(name: "#{session.id}.token")
        return evidence_failure("Credential changed", Code::CredentialChanged) unless Digest::SHA256.hexdigest(token) == session.credential_digest

        Kirei::Services::Result.new(result: live)
      end

      # A stop is proven by the recorded pane's absence.
      sig { params(session: Sessions::Dto::SessionView, pane_id: String).returns(Outcome) }
      private def prove_stop(session, pane_id)
        return failure(Code::EvidenceRejected, "Stop pane mismatch") unless session.pane_id == pane_id
        return failure(Code::EvidenceRejected, "Recorded pane still exists") if @herdr.panes.any? { |pane| pane.pane_id == pane_id }

        Kirei::Services::Result.new(result: pane_id)
      end

      # A proven start binds the live pane's identity and status; a stop deactivates.
      sig { params(session: Sessions::Dto::SessionView, pane_id: String, live: T.nilable(Adapters::Herdr::Dto::Pane)).void }
      private def apply(session, pane_id, live)
        if live
          @operations.activate_reconciled(session_id: session.id, pane_id: pane_id, identity: Identity.from_live(T.must(live.agent_session)),
                                          state: Sessions::Dto::SessionState.deserialize(live.agent_status.serialize), credential_expires_at: Time.now + 3600)
        else
          @operations.deactivate(session_id: session.id)
        end
      end

      sig do
        params(operation: Sessions::Dto::OperationView, session: Sessions::Dto::SessionView, inbox_id: String, pane_id: String,
               delivery: Messaging::Dto::VerifiedDelivery).void
      end
      private def record(operation, session, inbox_id, pane_id, delivery)
        key = "session:recovery:#{operation.id}"
        details = Sessions::Dto::SessionRecoveryAudit.new(inbox_id: inbox_id, operation_id: operation.id, session_id: session.id, generation: session.generation, pane_id: pane_id)
        @audit.record(event_key: key, action: "verified_session_reconciliation", details: details)
        message = Messaging::Dto::OutgoingMessage.new(
          channel_id: delivery.channel_id,
          thread_id: delivery.thread_id,
          bot: Messaging::Dto::Bot::Agent,
          role: Messaging::Dto::SpeakerRole::Controller,
          body: "Session operation #{operation.id} reconciled against runtime evidence; no start or stop was repeated.",
          key: key
        )
        Platform::Unwrap.call(@outbox.enqueue(message: message))
      end

      # The workflow's verified source, or the Controller's first human request.
      sig { params(session: Sessions::Dto::SessionView, workflow: T.nilable(Workflow)).returns(T.nilable(Messaging::Dto::InboxRecord)) }
      private def original_source(session, workflow)
        original_id = if workflow
                        workflow.source_inbox_id
                      else
                        value = @db[:master_requests].where(session_id: session.id).order(:inbox_id).get(:inbox_id)
                        value.is_a?(String) ? value : nil
                      end
        original_id && @inbox.find(id: original_id)
      end

      sig { params(detail: String, code: Code).returns(Evidence) }
      private def evidence_failure(detail, code = Code::EvidenceRejected)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
