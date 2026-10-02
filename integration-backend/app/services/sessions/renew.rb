# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    # Handles session.renew: extends the credential of the same live
    # conversation by one hour and schedules the next renewal. A replaced
    # generation, changed conversation or changed credential file fails.
    class Renew
      extend T::Sig
      include Platform::Jobs::Handler

      Code = Dto::ErrorCode
      Decision = Platform::Jobs::Dto::Decision
      Sessions = Domains::Sessions
      Workflow = Domains::Workflows::Dto::WorkflowView
      Outcome = T.type_alias { Kirei::Services::Result[String] }

      sig do
        params(herdr: Adapters::Herdr::Client, source: Domains::Messaging::VerifyHumanSource, credentials: Adapters::Credentials::FileStore,
               policy: Domains::Workflows::Policy, registry: Sessions::Registry, renewals: Sessions::Renewals, catalog: Domains::Workflows::Catalog,
               lock: Platform::Lock).void
      end
      def initialize(herdr:, source:, credentials:, policy: Domains::Workflows::Policy.new, registry: Sessions::Registry.new, renewals: Sessions::Renewals.new,
                     catalog: Domains::Workflows::Catalog.new, lock: Platform::Lock.new)
        @herdr = herdr
        @source = source
        @credentials = credentials
        @policy = policy
        @registry = registry
        @renewals = renewals
        @catalog = catalog
        @lock = lock
      end

      # Failures raise, so the worker keeps today's retry path.
      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          next Decision.block("Live session renewal evidence required") unless @policy.dispatch_allowed?

          payload = Sessions::Dto::RenewalJob.from_hash(job.payload, true)
          Platform::Unwrap.call(renew(payload.session_id, payload.generation))
          Decision.complete
        end
      end

      sig { params(session_id: String, generation: Integer).returns(Outcome) }
      private def renew(session_id, generation)
        session = renewable(session_id, generation)
        return inactive unless session

        @lock.call(key: session.workflow_id || "controller") do
          current = renewable(session_id, generation)
          next inactive unless current
          next failure(Code::SessionReplaced, "Session replaced") unless @registry.latest_generation(workflow_id: current.workflow_id, role: current.role) == generation

          workflow = workflow_for(current.workflow_id)
          if workflow
            verified = verify_source(workflow)
            next verified if verified.failed?
          end
          verify_and_extend(current)
        end
      end

      sig { params(session: Sessions::Dto::SessionView).returns(Outcome) }
      private def verify_and_extend(session)
        live = @herdr.pane(session.pane_id)
        unless Adapters::Herdr::ConversationIdentity.same?(session.runtime_identity, live.agent_session) && live.agent_status.live?
          return failure(Code::IdentityUnproven, "Session identity not proven")
        end

        token = @credentials.read(name: "#{session.id}.token")
        return failure(Code::CredentialChanged, "Credential changed") unless Digest::SHA256.hexdigest(token) == session.credential_digest

        Platform::Transaction.new.call do
          @renewals.extend_credential(session_id: session.id, expires_at: Time.now + 3600)
          @renewals.schedule(session: T.must(@registry.find(id: session.id)))
        end
        Kirei::Services::Result.new(result: session.id)
      end

      sig { params(session_id: String, generation: Integer).returns(T.nilable(Sessions::Dto::SessionView)) }
      private def renewable(session_id, generation)
        session = @registry.find(id: session_id)
        session if session && session.generation == generation && session.active
      end

      sig { params(workflow: Workflow).returns(Outcome) }
      private def verify_source(workflow)
        inbox_id = workflow.source_inbox_id
        return failure(Code::MissingSource, "Missing verified source") unless inbox_id

        verified = @source.call(inbox_id: inbox_id, destination: workflow.channel_id)
        return Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

        Kirei::Services::Result.new(result: inbox_id)
      end

      sig { params(workflow_id: T.nilable(String)).returns(T.nilable(Workflow)) }
      private def workflow_for(workflow_id) = workflow_id && @catalog.find(id: workflow_id)

      sig { returns(Outcome) }
      private def inactive = failure(Code::InactiveRenewal, "Inactive renewal session")

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
