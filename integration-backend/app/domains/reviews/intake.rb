# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    # Validates the short-lived callback capability before durable queueing. Git
    # and Herdr evidence are intentionally checked by the worker that owns them.
    class Intake
      extend T::Sig

      sig do
        params(token: String, generation: Integer, action: String, commit: String, kind: T.nilable(String), verdict: T.nilable(String)).returns(String)
      end
      def enqueue(token:, generation:, action:, commit:, kind: nil, verdict: nil)
        role = callback_role(action)
        validate_callback!(action: action, generation: generation, commit: commit, kind: kind, verdict: verdict)

        session = active_session(token: token, generation: generation, role: role)
        payload = callback_payload(session_id: session.id, generation: generation, action: action, commit: commit, kind: kind, verdict: verdict)
        # The digest covers the serialized payload; CallbackJob prop order keeps it stable.
        key = "review:callback:#{Digest::SHA256.hexdigest(JSON.generate(payload.serialize))}"
        Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::ReviewCallback, payload: payload, dispatch_key: key)
        "queued"
      end

      sig { params(action: String).returns(String) }
      private def callback_role(action)
        raise ArgumentError, "Invalid callback" unless %w[artifact review].include?(action)

        action == "artifact" ? "writer" : "reviewer"
      end

      sig { params(action: String, generation: Integer, commit: String, kind: T.nilable(String), verdict: T.nilable(String)).void }
      private def validate_callback!(action:, generation:, commit:, kind:, verdict:)
        raise ArgumentError, "Invalid callback" unless generation >= 0 && commit.match?(/\A[0-9a-f]{40}\z/)
        raise ArgumentError, "Invalid artifact" if action == "artifact" && !%w[spec plan implementation].include?(kind)
        raise ArgumentError, "Invalid verdict" if action == "review" && !%w[approve changes_requested].include?(verdict)
      end

      sig { params(token: String, generation: Integer, role: String).returns(Domains::Sessions::Dto::SessionView) }
      private def active_session(token:, generation:, role:)
        roles = [Domains::Sessions::Dto::SessionRole.deserialize(role)]
        # Every failure detail is "Invalid session"; Unwrap raises it as an ArgumentError.
        Platform::Unwrap.call(Domains::Sessions::Authenticate.new.call(token: token, generation: generation, roles: roles))
      end

      sig { params(session_id: String, generation: Integer, action: String, commit: String, kind: T.nilable(String), verdict: T.nilable(String)).returns(Dto::CallbackJob) }
      private def callback_payload(session_id:, generation:, action:, commit:, kind:, verdict:)
        if action == "artifact"
          raise ArgumentError, "Invalid artifact" unless kind

          Dto::CallbackJob.new(session_id: session_id, generation: generation, action: action, commit: commit, kind: kind)
        else
          raise ArgumentError, "Invalid verdict" unless verdict

          Dto::CallbackJob.new(session_id: session_id, generation: generation, action: action, commit: commit, verdict: verdict)
        end
      end
    end
  end
end
