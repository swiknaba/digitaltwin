# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    # Queues a Worker/Reviewer chat message in the thread bound to the
    # session's workflow. The callback key makes retries idempotent. The
    # callbacks rows stay raw until Task 7.
    class PostWorkerChat
      extend T::Sig

      Messaging = Domains::Messaging
      Session = Domains::Sessions::RuntimeSession
      Code = Dto::ErrorCode
      Phase = Domains::Workflows::Dto::Phase
      Workflow = Domains::Workflows::Dto::WorkflowView
      Outcome = T.type_alias { Kirei::Services::Result[Dto::QueuedChat] }
      RowValue = T.type_alias { T.any(String, Integer, Time, NilClass, T::Boolean) }
      Row = T.type_alias { T::Hash[Symbol, RowValue] }
      ROLES = T.let({ "writer" => Messaging::Dto::SpeakerRole::Writer, "reviewer" => Messaging::Dto::SpeakerRole::Reviewer }.freeze,
                    T::Hash[String, Messaging::Dto::SpeakerRole])
      WRITER_PHASES = T.let([Phase::SpecWriting, Phase::SpecHumanApproval, Phase::PlanWriting, Phase::PlanHumanApproval, Phase::Implementation,
                             Phase::PrReady, Phase::Done].freeze, T::Array[Phase])

      sig { params(outbox: Messaging::Outbox, catalog: Domains::Workflows::Catalog).void }
      def initialize(outbox: Messaging::Outbox.new, catalog: Domains::Workflows::Catalog.new)
        @outbox = outbox
        @catalog = catalog
      end

      sig { params(token: String, generation: Integer, body: String, key: String).returns(Outcome) }
      def call(token:, generation:, body:, key:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          next failure(Code::InvalidCallback, "Invalid callback") unless valid_request?(token, body, key)

          db = Session.db
          db.transaction do
            result = queue(token, generation, body, key)
            # A failure after the callback insert must not leave the receipt.
            db.rollback_on_exit if result.failed?
            result
          end
        rescue Errors::MalformedRecord, Domains::Workflows::Errors::MalformedRecord => error
          failure(Code::MalformedRecord, error.message)
        end
      end

      sig { params(token: String, body: String, key: String).returns(T::Boolean) }
      private def valid_request?(token, body, key)
        !token.empty? && body.bytesize.between?(1, 60_000) && key.match?(/\A[A-Za-z0-9_.:-]{1,200}\z/)
      end

      sig { params(token: String, generation: Integer, body: String, key: String).returns(Outcome) }
      private def queue(token, generation, body, key)
        session = Session.resolve_first(Session.query.where(credential_digest: Digest::SHA256.hexdigest(token), generation: generation, active: true).for_update)
        return failure(Code::InvalidSession, "Invalid or stale session") unless session && valid_session?(session)

        workflow_id = session.workflow_id
        return failure(Code::InvalidSession, "Invalid or stale session") unless workflow_id

        workflow = @catalog.find_for_update(id: workflow_id)
        raise Errors::MalformedRecord, "Invalid workflow" unless workflow
        return failure(Code::InactiveWorkflow, "Inactive workflow") unless workflow.archived_at.nil? && !workflow.phase.terminal?

        role = ROLES[session.role]
        return failure(Code::InactiveRole, "Session role is not active in this phase") unless role && session.role == active_role(workflow)

        db = Session.db
        latest = Session.query.where(workflow_id: workflow_id, role: session.role).max(:generation)
        return failure(Code::StaleGeneration, "Stale session generation") unless latest == generation

        digest = Digest::SHA256.hexdigest(body)
        db[:callbacks].insert_conflict(target: %i[session_id generation key]).insert(id: Platform::HumanId.call(prefix: "callback"), session_id: session.id, generation: generation, key: key, body_digest: digest)
        callback = row_from(db[:callbacks][session_id: session.id, generation: generation, key: key], "callback")
        return failure(Code::CallbackKeyReused, "Callback key reused with changed body") unless row_string(callback, :body_digest) == digest

        message = Messaging::Dto::OutgoingMessage.new(channel_id: workflow.channel_id, thread_id: workflow.thread_id, bot: Messaging::Dto::Bot::Worker, role: role,
                                                      body: "[#{session.role}] #{body}", key: "callback:#{session.id}:#{generation}:#{key}")
        enqueued = @outbox.enqueue(message: message)
        return Kirei::Services::Result.new(errors: enqueued.errors) if enqueued.failed?

        Kirei::Services::Result.new(result: Dto::QueuedChat.new(outbox_id: enqueued.result))
      end

      sig { params(session: Session).returns(T::Boolean) }
      private def valid_session?(session)
        session.credential_expires_at > Time.now && ROLES.key?(session.role)
      end

      sig { params(workflow: Workflow).returns(T.nilable(String)) }
      private def active_role(workflow)
        phase = workflow.effective_phase
        return nil unless phase
        return "reviewer" if phase.review?
        return "writer" if WRITER_PHASES.include?(phase)

        nil
      end

      sig { params(value: Object, name: String).returns(Row) }
      private def row_from(value, name)
        raise Errors::MalformedRecord, "Invalid #{name}" unless value.is_a?(Hash)

        row = T.let({}, Row)
        value.each do |key, item|
          raise Errors::MalformedRecord, "Invalid #{name}" unless key.is_a?(Symbol)

          # Sequel returns JSONB columns as a Hash subclass. This use case
          # reads no JSONB column, so it skips them.
          next if item.is_a?(Hash) || item.is_a?(Sequel::Postgres::JSONBHash)
          raise Errors::MalformedRecord, "Invalid #{name}" unless row_value?(item)

          row[key] = item
        end
        row
      end

      sig { params(value: Object).returns(T::Boolean) }
      private def row_value?(value)
        value.is_a?(String) || value.is_a?(Integer) || value.is_a?(Time) || value.nil? || value == true || value == false
      end

      sig { params(row: Row, key: Symbol).returns(String) }
      private def row_string(row, key)
        value = row.fetch(key)
        raise Errors::MalformedRecord, "Malformed database record" unless value.is_a?(String)

        value
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
