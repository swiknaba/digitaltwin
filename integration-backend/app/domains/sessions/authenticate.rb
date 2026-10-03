# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    # Authenticates a session callback credential. The session must hold the
    # token digest, be active with an allowed role, be unexpired, and be the
    # latest generation of its scope. Every failure has the detail
    # "Invalid session", so a caller learns nothing about the credential.
    class Authenticate
      extend T::Sig

      Outcome = T.type_alias { Kirei::Services::Result[Dto::SessionView] }

      sig { params(registry: Registry).void }
      def initialize(registry: Registry.new)
        @registry = registry
      end

      sig { params(token: String, generation: Integer, roles: T::Array[Dto::SessionRole]).returns(Outcome) }
      def call(token:, generation:, roles:)
        session = @registry.find_by_credential(digest: Digest::SHA256.hexdigest(token), generation: generation)
        return failure(Dto::ErrorCode::InvalidSession) unless session && roles.include?(session.role)

        latest = @registry.latest_generation(workflow_id: session.workflow_id, role: session.role)
        return failure(Dto::ErrorCode::StaleGeneration) unless latest == generation
        return failure(Dto::ErrorCode::InvalidSession) unless session.credential_expires_at > Time.now

        Kirei::Services::Result.new(result: session)
      end

      sig { params(code: Dto::ErrorCode).returns(Outcome) }
      private def failure(code)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: "Invalid session"))
      end
    end
  end
end
