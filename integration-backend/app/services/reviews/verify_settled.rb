# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    # Requires the session's recorded conversation to be live and settled in Herdr.
    class VerifySettled
      extend T::Sig

      sig { params(herdr: Adapters::Herdr::Client).void }
      def initialize(herdr:)
        @herdr = herdr
      end

      sig { params(session: Domains::Sessions::Dto::SessionView).void }
      def call(session:)
        live = @herdr.pane(session.pane_id)
        raise ArgumentError, "Session not settled or replaced" unless live.agent_session&.serialize == runtime_identity(session) && live.agent_status.settled?
      end

      # Review sessions are always started, so a missing identity is a malformed record.
      sig { params(session: Domains::Sessions::Dto::SessionView).returns(T::Hash[String, String]) }
      private def runtime_identity(session)
        identity = session.runtime_identity
        raise ArgumentError, Domains::Reviews::Rounds::MALFORMED unless identity

        identity.serialize
      end
    end
  end
end
