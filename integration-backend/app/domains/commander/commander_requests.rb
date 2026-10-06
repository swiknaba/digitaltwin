# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    # Verified human requests for the Commander conversation and their
    # request-bound credential digests. Callers hold the "commander"
    # Platform::Lock for state changes. Reads fail closed with
    # Errors::MalformedRecord on a row that does not match its typed shape.
    class CommanderRequests
      extend T::Sig

      State = Dto::CommanderRequestState
      MALFORMED = "Malformed durable Commander request record"

      # Idempotent on inbox_id: a second create returns the first request.
      sig { params(inbox_id: String, session_id: String, credential_digest: String, expires_at: Time).returns(Kirei::Services::Result[Dto::CommanderRequestView]) }
      def create(inbox_id:, session_id:, credential_digest:, expires_at:)
        existing = for_inbox(inbox_id: inbox_id)
        return Kirei::Services::Result.new(result: existing) if existing

        entity = Entities::CommanderRequest.create(id: SecureRandom.uuid, inbox_id: inbox_id, session_id: session_id, credential_digest: credential_digest,
                                                   expires_at: expires_at, state: State::Queued.serialize)
        Kirei::Services::Result.new(result: view(entity))
      end

      # The unexpired request in one of `states` whose credential digest matches.
      sig { params(id: String, token_digest: String, states: T::Array[State], now: Time).returns(Kirei::Services::Result[Dto::CommanderRequestView]) }
      def authorize(id:, token_digest:, states:, now: Time.now)
        request = first(Entities::CommanderRequest.query.where(id: id, credential_digest: token_digest, state: states.map(&:serialize)))
        return Kirei::Services::Result.new(result: request) if request && request.expires_at > now

        Kirei::Services::Result.new(errors: Platform::Failure.call(code: Dto::ErrorCode::CapabilityRejected, detail: "Request capability expired or inactive"))
      end

      # Fails closed unless one and only one unexpired request in `states`
      # matches the credential digest. This supports a deliberately narrow
      # token-only capability check for a read-only local reporting tool.
      sig { params(token_digest: String, states: T::Array[State], now: Time).returns(Kirei::Services::Result[Dto::CommanderRequestView]) }
      def authorize_token(token_digest:, states:, now: Time.now)
        matches = all(Entities::CommanderRequest.query.where(credential_digest: token_digest, state: states.map(&:serialize)))
        request = matches.one? ? matches.first : nil
        return Kirei::Services::Result.new(result: request) if request && request.expires_at > now

        Kirei::Services::Result.new(errors: Platform::Failure.call(code: Dto::ErrorCode::CapabilityRejected, detail: "Request capability expired or inactive"))
      end

      # Sets the state, and the reason when one is given.
      sig { params(id: String, state: State, reason: T.nilable(String)).void }
      def mark(id:, state:, reason: nil)
        changes = T.let({ state: state.serialize }, T::Hash[Symbol, String])
        changes[:reason] = reason if reason
        Entities::CommanderRequest.query.where(id: id).update(changes)
      end

      sig { params(id: String).returns(T.nilable(Dto::CommanderRequestView)) }
      def find(id:) = first(Entities::CommanderRequest.query.where(id: id))

      # Takes a row lock inside the caller's transaction.
      sig { params(id: String).returns(T.nilable(Dto::CommanderRequestView)) }
      def lock(id:) = first(Entities::CommanderRequest.query.where(id: id).for_update)

      sig { params(inbox_id: String).returns(T.nilable(Dto::CommanderRequestView)) }
      def for_inbox(inbox_id:) = first(Entities::CommanderRequest.query.where(inbox_id: inbox_id))

      # Inbox ids of the session's requests, unordered. Ids are random strings,
      # so callers order chronologically through Messaging::Inbox#earliest.
      sig { params(session_id: String).returns(T::Array[String]) }
      def inbox_ids_for_session(session_id:) = Entities::CommanderRequest.query.where(session_id: session_id).select_map(:inbox_id).grep(String)

      sig { params(session_id: String, state: State).returns(T::Array[Dto::CommanderRequestView]) }
      def in_state(session_id:, state:) = all(Entities::CommanderRequest.query.where(session_id: session_id, state: state.serialize))

      # Active requests of the session whose capability expired at `now`.
      sig { params(session_id: String, now: Time).returns(T::Array[Dto::CommanderRequestView]) }
      def expired_active(session_id:, now:)
        all(Entities::CommanderRequest.query.where(session_id: session_id, state: State::Active.serialize).where(Sequel.expr(:expires_at) <= now))
      end

      # Whether another request of the session is in one of `states`.
      sig { params(session_id: String, states: T::Array[State], except_id: String).returns(T::Boolean) }
      def other_in?(session_id:, states:, except_id:)
        !Entities::CommanderRequest.query.where(session_id: session_id, state: states.map(&:serialize)).exclude(id: except_id).empty?
      end

      sig { params(query: Sequel::Dataset).returns(T.nilable(Dto::CommanderRequestView)) }
      private def first(query) = all(query.limit(1)).first

      sig { params(query: Sequel::Dataset).returns(T::Array[Dto::CommanderRequestView]) }
      private def all(query) = strictly { Entities::CommanderRequest.resolve(query, true) }.map { |entity| view(entity) }

      sig { params(entity: Entities::CommanderRequest).returns(Dto::CommanderRequestView) }
      private def view(entity)
        Dto::CommanderRequestView.new(id: entity.id, inbox_id: entity.inbox_id, session_id: entity.session_id, credential_digest: entity.credential_digest,
                                      expires_at: entity.expires_at, state: entity.state, reason: entity.reason)
      end

      # from_hash raises RuntimeError for missing or unknown props and KeyError
      # for unknown enum values; constructors raise TypeError for wrong types.
      sig { type_parameters(:R).params(blk: T.proc.returns(T.type_parameter(:R))).returns(T.type_parameter(:R)) }
      private def strictly(&blk)
        yield
      rescue RuntimeError, KeyError, TypeError
        raise Errors::MalformedRecord, MALFORMED
      end
    end
  end
end
