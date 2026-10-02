# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class WorkerChat
      extend T::Sig

      RowValue = T.type_alias { T.any(String, Integer, Time, NilClass, T::Boolean) }
      Row = T.type_alias { T::Hash[Symbol, RowValue] }

      sig { params(token: String, generation: Integer, body: String, key: String).returns(Domains::Workflows::Entities::Outcome) }
      def post(token:, generation:, body:, key:)
        validate_request!(token, body, key)
        Domains::Sessions::RuntimeSession.db.transaction do
          session = Domains::Sessions::RuntimeSession.resolve_first(
            Domains::Sessions::RuntimeSession.query.where(
              credential_digest: Digest::SHA256.hexdigest(token), generation: generation, active: true
            ).for_update
          )
          raise ArgumentError, "Invalid or stale session" unless session

          validate_session!(session)
          raise ArgumentError, "Invalid or stale session" unless session.workflow_id

          database = Domains::Sessions::RuntimeSession.db
          workflow = workflow_from(database[:workflows].where(id: session.workflow_id).for_update.first)
          validate_workflow!(workflow)
          validate_role!(session, workflow)
          latest = Domains::Sessions::RuntimeSession.query.where(workflow_id: session.workflow_id, role: session.role).max(:generation)
          raise ArgumentError, "Stale session generation" unless latest == generation

          digest = Digest::SHA256.hexdigest(body)
          database[:callbacks].insert_conflict(target: %i[session_id generation key]).insert(session_id: session.id, generation: generation, key: key, body_digest: digest)
          callback = row_from(database[:callbacks][session_id: session.id, generation: generation, key: key], "callback")
          raise ArgumentError, "Callback key reused with changed body" unless row_string(callback, :body_digest) == digest

          Outbox.new.enqueue(channel_id: workflow.channel_id, thread_id: workflow.thread_id, bot: "worker", role: session.role,
                             body: "[#{session.role}] #{body}", key: "callback:#{session.id}:#{generation}:#{key}")
          outcome("accepted", "Queued in bound thread")
        end
      rescue ArgumentError => error
        outcome("rejected", error.message)
      end

      sig { params(token: String, body: String, key: String).void }
      private def validate_request!(token, body, key)
        return if !token.empty? && body.bytesize.between?(1, 60_000) && key.match?(/\A[A-Za-z0-9_.:-]{1,200}\z/)

        raise ArgumentError, "Invalid callback"
      end

      sig { params(value: Object, name: String).returns(Row) }
      private def row_from(value, name)
        raise ArgumentError, "Invalid #{name}" unless value.is_a?(Hash)

        row = T.let({}, Row)
        value.each do |key, item|
          raise ArgumentError, "Invalid #{name}" unless key.is_a?(Symbol)

          # Sequel returns JSONB columns as a Hash subclass. This command does
          # not consume any JSONB column, so keep it outside the scalar row
          # DTO instead of asking Sorbet's runtime `Object` contract to
          # nominally validate the adapter-owned wrapper.
          next if item.is_a?(Hash) || item.is_a?(Sequel::Postgres::JSONBHash)

          raise ArgumentError, "Invalid #{name}" unless row_value?(item)

          row[key] = item
        end
        row
      end

      sig { params(value: Object).returns(T::Boolean) }
      private def row_value?(value)
        value.is_a?(String) || value.is_a?(Integer) || value.is_a?(Time) || value.nil? || value == true || value == false
      end

      sig { params(value: Object).returns(Workflow) }
      private def workflow_from(value)
        row = row_from(value, "workflow")
        Workflow.new(channel_id: row_string(row, :channel_id), thread_id: row_string(row, :thread_id), phase: row_string(row, :phase),
                     saved_phase: optional_row_string(row, :saved_phase), archived_at: optional_row_time(row, :archived_at))
      end

      sig { params(session: Domains::Sessions::RuntimeSession).void }
      private def validate_session!(session)
        raise ArgumentError, "Invalid or stale session" unless session.credential_expires_at > Time.now && %w[writer reviewer].include?(session.role)
      end

      sig { params(workflow: Workflow).void }
      private def validate_workflow!(workflow)
        raise ArgumentError, "Inactive workflow" unless workflow.archived_at.nil? && !%w[cancelled closed].include?(workflow.phase)
      end

      sig { params(session: Domains::Sessions::RuntimeSession, workflow: Workflow).void }
      private def validate_role!(session, workflow)
        phase = workflow.phase == "paused" ? workflow.saved_phase : workflow.phase
        raise ArgumentError, "Session role is not active in this phase" unless session.role == active_role(phase)
      end

      sig { params(phase: T.nilable(String)).returns(T.nilable(String)) }
      private def active_role(phase)
        return "reviewer" if %w[spec_review plan_review implementation_review].include?(phase)
        return "writer" if %w[spec_writing spec_human_approval plan_writing plan_human_approval implementation pr_ready done].include?(phase)

        nil
      end

      sig { params(row: Row, key: Symbol).returns(String) }
      private def row_string(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Malformed database record" unless value.is_a?(String)

        value
      end

      sig { params(row: Row, key: Symbol).returns(T.nilable(String)) }
      private def optional_row_string(row, key)
        value = row[key]
        raise ArgumentError, "Malformed database record" unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(row: Row, key: Symbol).returns(T.nilable(Time)) }
      private def optional_row_time(row, key)
        value = row[key]
        raise ArgumentError, "Malformed database record" unless value.nil? || value.is_a?(Time)

        value
      end

      sig { params(status: String, reason: String).returns(Domains::Workflows::Entities::Outcome) }
      private def outcome(status, reason)
        Domains::Workflows::Entities::Outcome.new(status: status, reason: reason)
      end
    end
  end
end
