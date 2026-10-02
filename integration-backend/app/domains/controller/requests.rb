# typed: strict
# frozen_string_literal: true

module Domains
  module Controller
    class Requests
      extend T::Sig

      RequestRow = T.type_alias { T::Hash[Symbol, Object] }
      SessionRow = T.type_alias { T::Hash[Symbol, Object] }

      sig { params(db: Sequel::Database, source: Source).void }
      def initialize(db, source:)
        @db = db
        @source = source
      end

      sig { params(id: String, token: String, states: T::Array[String]).returns(RequestRow) }
      def authorize(id, token, states: ["active"])
        r = @db[:master_requests][id: id, credential_digest: Digest::SHA256.hexdigest(token), state: states]
        s = r && @db[:sessions][id: r[:session_id], role: "controller", active: true]
        latest = @db[:sessions].where(role: "controller").max(:generation)
        raise ArgumentError, "Request capability expired or inactive" unless r.is_a?(Hash) && s.is_a?(Hash) && valid_request?(r, s, latest)

        @source.human(inbox_id(r))
        r
      end

      private

      sig { params(request: RequestRow, session: SessionRow, latest_generation: Object).returns(T::Boolean) }
      def valid_request?(request, session, latest_generation)
        expires_at(request, :expires_at) > Time.now &&
          expires_at(session, :credential_expires_at) > Time.now &&
          integer_value(session, :generation) == latest_generation
      end

      sig { params(request: RequestRow).returns(T.any(Integer, String)) }
      def inbox_id(request)
        value = request.fetch(:inbox_id)
        raise ArgumentError, "Invalid request capability" unless value.is_a?(Integer) || value.is_a?(String)

        value
      end

      sig { params(row: T::Hash[Symbol, Object], key: Symbol).returns(Time) }
      def expires_at(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Invalid request capability" unless value.is_a?(Time)

        value
      end

      sig { params(row: T::Hash[Symbol, Object], key: Symbol).returns(Integer) }
      def integer_value(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Invalid request capability" unless value.is_a?(Integer)

        value
      end
    end
  end
end
