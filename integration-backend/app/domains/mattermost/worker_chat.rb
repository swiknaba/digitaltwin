# typed: strict
# frozen_string_literal: true

require "digest"

module Domains
  module Mattermost
    class WorkerChat
      extend T::Sig

      RowValue = T.type_alias { T.any(String, Integer, Time, NilClass, T::Boolean) }
      Row = T.type_alias { T::Hash[Symbol, RowValue] }

      class Session < T::Struct
        const :id, String
        const :workflow_id, String
        const :role, String
        const :generation, Integer
        const :credential_expires_at, Time
      end

      class Workflow < T::Struct
        const :channel_id, String
        const :thread_id, String
        const :phase, String
        const :saved_phase, T.nilable(String)
        const :archived_at, T.nilable(Time)
      end

      sig { params(db: Sequel::Database).void }
      def initialize(db)
        @db = T.let(db, Sequel::Database)
      end

      sig { params(token: String, generation: Integer, body: String, key: String).returns(Domains::Workflows::Entities::Outcome) }
      def post(token:, generation:, body:, key:)
        validate_request!(token, body, key)
        @db.transaction do
          session = session_from(@db[:sessions].where(credential_digest: Digest::SHA256.hexdigest(token), generation: generation, active: true).for_update.first)
          validate_session!(session)
          workflow = workflow_from(@db[:workflows].where(id: session.workflow_id).for_update.first)
          validate_workflow!(workflow)
          validate_role!(session, workflow)
          latest = @db[:sessions].where(workflow_id: session.workflow_id, role: session.role).max(:generation)
          raise ArgumentError, "Stale session generation" unless latest == generation

          digest = Digest::SHA256.hexdigest(body)
          @db[:callbacks].insert_conflict(target: %i[session_id generation key]).insert(session_id: session.id, generation: generation, key: key, body_digest: digest)
          callback = row_from(@db[:callbacks][session_id: session.id, generation: generation, key: key], "callback")
          raise ArgumentError, "Callback key reused with changed body" unless row_string(callback, :body_digest) == digest

          Outbox.new(@db).enqueue(channel_id: workflow.channel_id, thread_id: workflow.thread_id, bot: "worker", role: session.role,
                                  body: "[#{session.role}] #{body}", key: "callback:#{session.id}:#{generation}:#{key}")
          outcome("accepted", "Queued in bound thread")
        end
      rescue ArgumentError => error
        outcome("rejected", error.message)
      end

      private

      sig { params(token: String, body: String, key: String).void }
      def validate_request!(token, body, key)
        return if !token.empty? && body.bytesize.between?(1, 60_000) && key.match?(/\A[A-Za-z0-9_.:-]{1,200}\z/)

        raise ArgumentError, "Invalid callback"
      end

      sig { params(value: Object, name: String).returns(Row) }
      def row_from(value, name)
        raise ArgumentError, "Invalid #{name}" unless value.is_a?(Hash)

        row = T.let({}, Row)
        value.each do |key, item|
          raise ArgumentError, "Invalid #{name}" unless key.is_a?(Symbol) && row_value?(item)

          row[key] = item
        end
        row
      end

      sig { params(value: Object).returns(T::Boolean) }
      def row_value?(value)
        value.is_a?(String) || value.is_a?(Integer) || value.is_a?(Time) || value.nil? || value == true || value == false
      end

      sig { params(value: Object).returns(Session) }
      def session_from(value)
        row = row_from(value, "or stale session")
        Session.new(id: row_string(row, :id), workflow_id: row_string(row, :workflow_id), role: row_string(row, :role),
                    generation: row_integer(row, :generation), credential_expires_at: row_time(row, :credential_expires_at))
      end

      sig { params(value: Object).returns(Workflow) }
      def workflow_from(value)
        row = row_from(value, "workflow")
        Workflow.new(channel_id: row_string(row, :channel_id), thread_id: row_string(row, :thread_id), phase: row_string(row, :phase),
                     saved_phase: optional_row_string(row, :saved_phase), archived_at: optional_row_time(row, :archived_at))
      end

      sig { params(session: Session).void }
      def validate_session!(session)
        raise ArgumentError, "Invalid or stale session" unless session.credential_expires_at > Time.now && %w[writer reviewer].include?(session.role)
      end

      sig { params(workflow: Workflow).void }
      def validate_workflow!(workflow)
        raise ArgumentError, "Inactive workflow" unless workflow.archived_at.nil? && !%w[cancelled closed].include?(workflow.phase)
      end

      sig { params(session: Session, workflow: Workflow).void }
      def validate_role!(session, workflow)
        phase = workflow.phase == "paused" ? workflow.saved_phase : workflow.phase
        raise ArgumentError, "Session role is not active in this phase" unless session.role == active_role(phase)
      end

      sig { params(phase: T.nilable(String)).returns(T.nilable(String)) }
      def active_role(phase)
        return "reviewer" if %w[spec_review plan_review implementation_review].include?(phase)
        return "writer" if %w[spec_writing spec_human_approval plan_writing plan_human_approval implementation pr_ready done].include?(phase)

        nil
      end

      sig { params(row: Row, key: Symbol).returns(String) }
      def row_string(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Malformed database record" unless value.is_a?(String)

        value
      end

      sig { params(row: Row, key: Symbol).returns(Integer) }
      def row_integer(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Malformed database record" unless value.is_a?(Integer)

        value
      end

      sig { params(row: Row, key: Symbol).returns(Time) }
      def row_time(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Malformed database record" unless value.is_a?(Time)

        value
      end

      sig { params(row: Row, key: Symbol).returns(T.nilable(String)) }
      def optional_row_string(row, key)
        value = row[key]
        raise ArgumentError, "Malformed database record" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(row: Row, key: Symbol).returns(T.nilable(Time)) }
      def optional_row_time(row, key)
        value = row[key]
        raise ArgumentError, "Malformed database record" unless value.nil? || value.is_a?(Time)

        value
      end

      sig { params(status: String, reason: String).returns(Domains::Workflows::Entities::Outcome) }
      def outcome(status, reason)
        Domains::Workflows::Entities::Outcome.new(status: status, reason: reason)
      end
    end
  end
end
