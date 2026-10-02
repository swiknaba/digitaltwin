# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    class Requests
      extend T::Sig

      RequestRow = T.type_alias { T::Hash[Symbol, Object] }
      Session = Domains::Sessions::Dto::SessionView
      Controller = Domains::Sessions::Dto::SessionRole::Controller

      sig { params(db: Sequel::Database, source: Domains::Messaging::VerifyHumanSource, registry: Domains::Sessions::Registry).void }
      def initialize(db, source:, registry: Domains::Sessions::Registry.new)
        @db = db
        @source = source
        @registry = registry
      end

      sig { params(id: String, token: String, states: T::Array[String]).returns(RequestRow) }
      def authorize(id, token, states: ["active"])
        r = @db[:master_requests][id: id, credential_digest: Digest::SHA256.hexdigest(token), state: states]
        s = r && controller_session(r)
        latest = @registry.latest_generation(workflow_id: nil, role: Controller)
        raise ArgumentError, "Request capability expired or inactive" unless r.is_a?(Hash) && s && valid_request?(r, s, latest)

        Platform::Unwrap.call(@source.call(inbox_id: inbox_id(r)))
        r
      end

      sig { params(request: RequestRow).returns(T.nilable(Session)) }
      private def controller_session(request)
        id = request.fetch(:session_id)
        session = id.is_a?(String) ? @registry.find(id: id) : nil
        session if session && session.role == Controller && session.active
      end

      sig { params(request: RequestRow, session: Session, latest_generation: Integer).returns(T::Boolean) }
      private def valid_request?(request, session, latest_generation)
        expires_at(request, :expires_at) > Time.now &&
          session.credential_expires_at > Time.now &&
          session.generation == latest_generation
      end

      sig { params(request: RequestRow).returns(String) }
      private def inbox_id(request)
        value = request.fetch(:inbox_id)
        raise ArgumentError, "Invalid request capability" unless value.is_a?(String)

        value
      end

      sig { params(row: T::Hash[Symbol, Object], key: Symbol).returns(Time) }
      private def expires_at(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Invalid request capability" unless value.is_a?(Time)

        value
      end
    end
  end
end
