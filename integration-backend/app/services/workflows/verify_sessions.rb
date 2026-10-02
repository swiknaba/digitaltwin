# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Proves that a workflow's active sessions are the recorded conversations,
    # settled, and unexpired. An empty selection fails.
    class VerifySessions
      extend T::Sig

      Code = Dto::ErrorCode
      Session = Domains::Sessions::RuntimeSession
      Status = Adapters::Herdr::Dto::AgentStatus
      Outcome = T.type_alias { Kirei::Services::Result[T::Array[Session]] }
      SETTLED = T.let([Status::Idle, Status::Done].freeze, T::Array[Status])

      sig { params(herdr: Adapters::Herdr::Client).void }
      def initialize(herdr:)
        @herdr = herdr
      end

      sig { params(workflow_id: String, role: T.nilable(String)).returns(Outcome) }
      def call(workflow_id:, role: nil)
        query = Session.query.where(workflow_id: workflow_id, active: true)
        query = query.where(role: role) if role
        sessions = Session.resolve(query.order(:id))
        return failure(Code::SessionMissing, "Required session missing") if sessions.empty?

        sessions.each do |session|
          live = @herdr.pane(session.pane_id)
          identity = session.runtime_identity
          proven = identity && live.agent_session&.serialize == identity && SETTLED.include?(live.agent_status)
          return failure(Code::SessionUncertain, "Session uncertain or replaced") unless proven && session.credential_expires_at > Time.now
        end
        Kirei::Services::Result.new(result: sessions)
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
