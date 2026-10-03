# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    # Validates the short-lived callback capability before durable queueing.
    # Git and Herdr evidence are checked by ApplyCallback's job, which owns them.
    class QueueCallback
      extend T::Sig

      Code = Dto::ErrorCode
      Outcome = T.type_alias { Kirei::Services::Result[String] }
      Role = Domains::Sessions::Dto::SessionRole
      CallbackJob = Domains::Reviews::Dto::ReviewCallbackJob
      COMMIT = /\A[0-9a-f]{40}\z/

      sig { params(authenticate: Domains::Sessions::Authenticate, jobs: Platform::Jobs::Store).void }
      def initialize(authenticate: Domains::Sessions::Authenticate.new, jobs: Platform::Jobs::Store.new)
        @authenticate = authenticate
        @jobs = jobs
      end

      # Returns "queued". Every session failure detail is "Invalid session".
      sig do
        params(token: String, generation: Integer, action: String, commit: String, kind: T.nilable(String), verdict: T.nilable(String)).returns(Outcome)
      end
      def call(token:, generation:, action:, commit:, kind: nil, verdict: nil)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          role = callback_role(action)
          next failure(Code::InvalidCallback, "Invalid callback") unless role && generation >= 0 && commit.match?(COMMIT)
          next failure(Code::InvalidArtifact, "Invalid artifact") if action == "artifact" && !%w[spec plan implementation].include?(kind)
          next failure(Code::InvalidVerdict, "Invalid verdict") if action == "review" && !%w[approve changes_requested].include?(verdict)

          session = @authenticate.call(token: token, generation: generation, roles: [role])
          next Kirei::Services::Result.new(errors: session.errors) if session.failed?

          # Each action carries only its own field, so the payload JSON names one of kind or verdict.
          payload = CallbackJob.new(session_id: session.result.id, generation: generation, action: action, commit: commit,
                                    kind: role == Role::Writer ? kind : nil, verdict: role == Role::Reviewer ? verdict : nil)
          # The digest covers the serialized payload; ReviewCallbackJob prop order keeps it stable.
          key = "review:callback:#{Digest::SHA256.hexdigest(JSON.generate(payload.serialize))}"
          @jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::ReviewCallback, payload: payload, dispatch_key: key)
          Kirei::Services::Result.new(result: "queued")
        end
      end

      sig { params(action: String).returns(T.nilable(Role)) }
      private def callback_role(action)
        case action
        when "artifact" then Role::Writer
        when "review" then Role::Reviewer
        end
      end

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
