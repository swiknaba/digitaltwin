# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Proves that a workflow's active sessions are the recorded conversations,
    # settled, and unexpired. An empty selection fails.
    class VerifySessions
      extend T::Sig

      Code = Dto::ErrorCode
      Session = Domains::Sessions::Dto::SessionView
      Outcome = T.type_alias { Kirei::Services::Result[T::Array[Session]] }

      sig { params(herdr: Adapters::Herdr::Client, registry: Domains::Sessions::Registry).void }
      def initialize(herdr:, registry: Domains::Sessions::Registry.new)
        @herdr = herdr
        @registry = registry
      end

      # A nil role selects every active session of the workflow.
      sig { params(workflow_id: String, role: T.nilable(Domains::Sessions::Dto::SessionRole)).returns(Outcome) }
      def call(workflow_id:, role: nil)
        sessions = @registry.active(workflow_id: workflow_id, role: role)
        return failure(Code::SessionMissing, "Required session missing") if sessions.empty?

        sessions.each do |session|
          live = @herdr.pane(session.pane_id)
          proven = Adapters::Herdr::ConversationIdentity.same?(session.runtime_identity, live.agent_session) && live.agent_status.settled?
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
