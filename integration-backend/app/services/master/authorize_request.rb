# typed: strict
# frozen_string_literal: true

module Services
  module Master
    # Proves a Master request capability: the token digest of an unexpired
    # request in one of `states`, held by the active Controller of the latest
    # generation, whose human source still verifies.
    class AuthorizeRequest
      extend T::Sig

      Commander = Domains::Commander
      Controller = Domains::Sessions::Dto::SessionRole::Controller
      Outcome = T.type_alias { Kirei::Services::Result[Commander::Dto::MasterRequestView] }

      sig { params(source: Domains::Messaging::VerifyHumanSource, requests: Commander::MasterRequests, registry: Domains::Sessions::Registry).void }
      def initialize(source:, requests: Commander::MasterRequests.new, registry: Domains::Sessions::Registry.new)
        @source = source
        @requests = requests
        @registry = registry
      end

      sig { params(id: String, token: String, states: T::Array[Commander::Dto::MasterRequestState]).returns(Outcome) }
      def call(id:, token:, states:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          now = Time.now
          authorized = @requests.authorize(id: id, token_digest: Digest::SHA256.hexdigest(token), states: states, now: now)
          next authorized if authorized.failed?

          request = authorized.result
          session = @registry.find(id: request.session_id)
          latest = @registry.latest_generation(workflow_id: nil, role: Controller)
          valid = session && session.role == Controller && session.active && session.credential_expires_at > now && session.generation == latest
          next rejected unless valid

          verified = @source.call(inbox_id: request.inbox_id)
          next Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

          authorized
        end
      end

      sig { returns(Outcome) }
      private def rejected
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: Commander::Dto::ErrorCode::CapabilityRejected, detail: "Request capability expired or inactive"))
      end
    end
  end
end
