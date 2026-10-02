# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    # Queues a Worker/Reviewer chat message in the thread bound to the
    # session's workflow. The callback key makes retries idempotent.
    class PostWorkerChat
      extend T::Sig

      Messaging = Domains::Messaging
      Session = Domains::Sessions::Dto::SessionView
      SessionRole = Domains::Sessions::Dto::SessionRole
      Code = Dto::ErrorCode
      Phase = Domains::Workflows::Dto::Phase
      Workflow = Domains::Workflows::Dto::WorkflowView
      Outcome = T.type_alias { Kirei::Services::Result[Dto::QueuedChat] }
      ROLES = T.let({ SessionRole::Writer => Messaging::Dto::SpeakerRole::Writer, SessionRole::Reviewer => Messaging::Dto::SpeakerRole::Reviewer }.freeze,
                    T::Hash[SessionRole, Messaging::Dto::SpeakerRole])
      WRITER_PHASES = T.let([Phase::SpecWriting, Phase::SpecHumanApproval, Phase::PlanWriting, Phase::PlanHumanApproval, Phase::Implementation,
                             Phase::PrReady, Phase::Done].freeze, T::Array[Phase])

      sig do
        params(outbox: Messaging::Outbox, catalog: Domains::Workflows::Catalog, registry: Domains::Sessions::Registry, callbacks: Domains::Sessions::Callbacks,
               transaction: Platform::Transaction).void
      end
      def initialize(outbox: Messaging::Outbox.new, catalog: Domains::Workflows::Catalog.new, registry: Domains::Sessions::Registry.new,
                     callbacks: Domains::Sessions::Callbacks.new, transaction: Platform::Transaction.new)
        @outbox = outbox
        @catalog = catalog
        @registry = registry
        @callbacks = callbacks
        @transaction = transaction
      end

      sig { params(token: String, generation: Integer, body: String, key: String).returns(Outcome) }
      def call(token:, generation:, body:, key:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          next failure(Code::InvalidCallback, "Invalid callback") unless valid_request?(token, body, key)

          outcome = T.let(nil, T.nilable(Outcome))
          @transaction.call do
            outcome = queue(token, generation, body, key)
            # A failure after the callback insert must not leave the receipt.
            # The transaction swallows Sequel::Rollback.
            raise Sequel::Rollback if outcome.failed?
          end
          T.must(outcome)
        rescue Errors::MalformedRecord, Domains::Workflows::Errors::MalformedRecord, Domains::Sessions::Errors::MalformedRecord => error
          failure(Code::MalformedRecord, error.message)
        end
      end

      sig { params(token: String, body: String, key: String).returns(T::Boolean) }
      private def valid_request?(token, body, key)
        !token.empty? && body.bytesize.between?(1, 60_000) && key.match?(/\A[A-Za-z0-9_.:-]{1,200}\z/)
      end

      sig { params(token: String, generation: Integer, body: String, key: String).returns(Outcome) }
      private def queue(token, generation, body, key)
        session = @registry.lock_by_credential(digest: Digest::SHA256.hexdigest(token), generation: generation)
        return failure(Code::InvalidSession, "Invalid or stale session") unless session && valid_session?(session)

        workflow_id = session.workflow_id
        return failure(Code::InvalidSession, "Invalid or stale session") unless workflow_id

        workflow = @catalog.find_for_update(id: workflow_id)
        raise Errors::MalformedRecord, "Invalid workflow" unless workflow
        return failure(Code::InactiveWorkflow, "Inactive workflow") unless workflow.archived_at.nil? && !workflow.phase.terminal?

        role = ROLES[session.role]
        return failure(Code::InactiveRole, "Session role is not active in this phase") unless role && session.role == active_role(workflow)

        latest = @registry.latest_generation(workflow_id: workflow_id, role: session.role)
        return failure(Code::StaleGeneration, "Stale session generation") unless latest == generation

        recorded = @callbacks.record(session_id: session.id, generation: generation, key: key, body_digest: Digest::SHA256.hexdigest(body))
        return failure(Code::CallbackKeyReused, "Callback key reused with changed body") if recorded.failed?

        message = Messaging::Dto::OutgoingMessage.new(channel_id: workflow.channel_id, thread_id: workflow.thread_id, bot: Messaging::Dto::Bot::Worker, role: role,
                                                      body: "[#{session.role.serialize}] #{body}", key: "callback:#{session.id}:#{generation}:#{key}")
        enqueued = @outbox.enqueue(message: message)
        return Kirei::Services::Result.new(errors: enqueued.errors) if enqueued.failed?

        Kirei::Services::Result.new(result: Dto::QueuedChat.new(outbox_id: enqueued.result))
      end

      sig { params(session: Session).returns(T::Boolean) }
      private def valid_session?(session)
        session.credential_expires_at > Time.now && ROLES.key?(session.role)
      end

      sig { params(workflow: Workflow).returns(T.nilable(SessionRole)) }
      private def active_role(workflow)
        phase = workflow.effective_phase
        return nil unless phase
        return SessionRole::Reviewer if phase.review?
        return SessionRole::Writer if WRITER_PHASES.include?(phase)

        nil
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
