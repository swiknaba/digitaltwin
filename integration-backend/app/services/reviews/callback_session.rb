# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    # Resolves the active, latest-generation session of a review callback.
    # A bearer token is resolved first, then the session is checked again by id.
    class CallbackSession
      extend T::Sig

      Caller = T.type_alias { T.any(Dto::BearerToken, Dto::QueuedSession) }
      Session = Domains::Sessions::Dto::SessionView
      Role = Domains::Sessions::Dto::SessionRole
      MALFORMED = Domains::Reviews::Rounds::MALFORMED

      sig { params(registry: Domains::Sessions::Registry).void }
      def initialize(registry: Domains::Sessions::Registry.new)
        @registry = registry
      end

      sig { params(caller: Caller, generation: Integer, role: Role).returns(Session) }
      def call(caller:, generation:, role:)
        session_id = case caller
                     when Dto::BearerToken then by_token(caller.token, generation, role).id
                     when Dto::QueuedSession then caller.session_id
                     else T.absurd(caller)
                     end
        checked(session_id, generation, role)
      end

      sig { params(token: String, generation: Integer, role: Role).returns(Session) }
      private def by_token(token, generation, role)
        session = @registry.find_by_credential(digest: Digest::SHA256.hexdigest(token), generation: generation)
        raise ArgumentError, MALFORMED unless session && session.role == role

        latest = @registry.latest_generation(workflow_id: workflow_id(session), role: role)
        raise ArgumentError, "Invalid callback session" unless session.credential_expires_at > Time.now && latest == generation

        session
      end

      sig { params(id: String, generation: Integer, role: Role).returns(Session) }
      private def checked(id, generation, role)
        session = @registry.find(id: id)
        raise ArgumentError, MALFORMED unless session && session.generation == generation && session.active && session.role == role

        latest = @registry.latest_generation(workflow_id: workflow_id(session), role: role)
        raise ArgumentError, "Stale callback session" unless latest == generation && session.credential_expires_at > Time.now

        session
      end

      sig { params(session: Session).returns(String) }
      private def workflow_id(session)
        session.workflow_id or raise ArgumentError, MALFORMED
      end
    end
  end
end
