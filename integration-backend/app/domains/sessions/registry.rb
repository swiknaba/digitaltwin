# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    # Read access to sessions. A scope is one workflow role, or the commander
    # (workflow_id nil). Lists order by created_at, then id.
    class Registry
      extend T::Sig

      PENDING_STATES = T.let(Dto::OperationState.values.select(&:pending?).map(&:serialize).freeze, T::Array[String])

      # Credential file names embed the id, so callers generate it before the session row exists.
      sig { returns(String) }
      def next_id = Entities::RuntimeSession.generate_human_id

      sig { params(id: String).returns(T.nilable(Dto::SessionView)) }
      def find(id:) = Records.sessions(Entities::RuntimeSession.query.where(id: id)).first

      # The active session that holds this credential digest and generation.
      sig { params(digest: String, generation: Integer).returns(T.nilable(Dto::SessionView)) }
      def find_by_credential(digest:, generation:) = Records.sessions(credential_query(digest, generation)).first

      # As find_by_credential, and takes a row lock inside the caller's transaction.
      sig { params(digest: String, generation: Integer).returns(T.nilable(Dto::SessionView)) }
      def lock_by_credential(digest:, generation:) = Records.sessions(credential_query(digest, generation).for_update).first

      # Active sessions of a workflow; a nil role selects every role.
      sig { params(workflow_id: String, role: T.nilable(Dto::SessionRole)).returns(T::Array[Dto::SessionView]) }
      def active(workflow_id:, role:)
        query = Entities::RuntimeSession.query.where(workflow_id: workflow_id, active: true)
        query = query.where(role: role.serialize) if role
        Records.sessions(ordered(query))
      end

      sig { returns(T.nilable(Dto::SessionView)) }
      def active_commander
        Records.sessions(ordered(scope(nil, Dto::SessionRole::Commander).where(active: true))).first
      end

      sig { returns(T::Array[Dto::SessionView]) }
      def all_active = Records.sessions(ordered(Entities::RuntimeSession.query.where(active: true)))

      # Sessions of the scope whose start operation is queued, sending or uncertain.
      sig { params(workflow_id: T.nilable(String), role: Dto::SessionRole).returns(T::Array[Dto::SessionView]) }
      def pending_starts(workflow_id:, role:)
        starts = Entities::SessionOperation.query.where(kind: Dto::OperationKind::Start.serialize, state: PENDING_STATES).select(:session_id)
        Records.sessions(ordered(scope(workflow_id, role).where(id: starts)))
      end

      sig { params(workflow_id: T.nilable(String), role: Dto::SessionRole).returns(T.nilable(Dto::SessionView)) }
      def pending_start(workflow_id:, role:) = pending_starts(workflow_id: workflow_id, role: role).first

      # Highest generation of the scope, or 0 when the scope has no session.
      sig { params(workflow_id: T.nilable(String), role: Dto::SessionRole).returns(Integer) }
      def latest_generation(workflow_id:, role:)
        value = scope(workflow_id, role).max(:generation)
        value.is_a?(Integer) ? value : 0
      end

      sig { params(workflow_id: T.nilable(String), role: Dto::SessionRole).returns(Sequel::Dataset) }
      private def scope(workflow_id, role) = Entities::RuntimeSession.query.where(workflow_id: workflow_id, role: role.serialize)

      sig { params(digest: String, generation: Integer).returns(Sequel::Dataset) }
      private def credential_query(digest, generation)
        Entities::RuntimeSession.query.where(credential_digest: digest, generation: generation, active: true)
      end

      sig { params(query: Sequel::Dataset).returns(Sequel::Dataset) }
      private def ordered(query) = query.order(:created_at, :id)
    end
  end
end
