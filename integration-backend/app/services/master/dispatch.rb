# typed: strict
# frozen_string_literal: true

module Services
  module Master
    # Handles master.dispatch: prompts the settled Controller conversation
    # with one queued request at a time. Expired active requests become
    # uncertain and need human recovery; a request is marked uncertain before
    # the prompt and active after it, so a lost send is never repeated.
    class Dispatch
      extend T::Sig
      include Platform::Jobs::Handler

      Decision = Platform::Jobs::Dto::Decision
      State = Domains::Commander::Dto::MasterRequestState
      Messaging = Domains::Messaging
      Identity = Adapters::Herdr::ConversationIdentity
      Request = Domains::Commander::Dto::MasterRequestView

      sig do
        params(source: Messaging::VerifyHumanSource, herdr: Adapters::Herdr::Client, credentials: Adapters::Credentials::FileStore,
               policy: Domains::Workflows::Policy, requests: Domains::Commander::MasterRequests, registry: Domains::Sessions::Registry,
               inbox: Messaging::Inbox, outbox: Messaging::Outbox, lock: Platform::Lock).void
      end
      def initialize(source:, herdr:, credentials:, policy:, requests: Domains::Commander::MasterRequests.new, registry: Domains::Sessions::Registry.new,
                     inbox: Messaging::Inbox.new, outbox: Messaging::Outbox.new, lock: Platform::Lock.new)
        @source = source
        @herdr = herdr
        @credentials = credentials
        @policy = policy
        @requests = requests
        @registry = registry
        @inbox = inbox
        @outbox = outbox
        @lock = lock
      end

      # Unexpected states raise, so the worker keeps today's retry path.
      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          id = request_id(job)
          @lock.call(key: "controller") { dispatch(id, job.lease) }
        end
      end

      sig { params(id: String, lease: Platform::Jobs::Lease).returns(Decision) }
      private def dispatch(id, lease)
        r = @requests.find(id: id) or raise ArgumentError, "Unknown Master request"
        return Decision.complete if r.state == State::Active || r.state == State::Complete
        raise ArgumentError, "Master request uncertain" unless r.state == State::Queued
        return Decision.block("Selected Master CLI/MCP live evidence required") unless @policy.dispatch_allowed?

        @requests.expired_active(session_id: r.session_id, now: Time.now).each { |old| expire(old) }
        if @requests.other_in?(session_id: r.session_id, states: [State::Uncertain], except_id: r.id)
          return Decision.block("Prior Master request requires human reconciliation")
        end

        busy = @requests.other_in?(session_id: r.session_id, states: [State::Active, State::Uncertain], except_id: r.id)
        s = active_controller(r.session_id)
        return Decision.defer("Master startup or current request pending") if !s || busy
        raise ArgumentError, "Master request/session expired" unless r.expires_at > Time.now && s.credential_expires_at > Time.now

        d = Platform::Unwrap.call(@source.call(inbox_id: r.inbox_id))
        live = @herdr.pane(s.pane_id)
        same_conversation = Identity.same?(s.runtime_identity, live.agent_session)
        return Decision.defer("Master finishing current turn") if same_conversation && live.agent_status == Adapters::Herdr::Dto::AgentStatus::Working
        raise ArgumentError, "Master conversation replaced or uncertain" unless same_conversation && live.agent_status.settled?

        token = @credentials.read(name: "#{r.id}.request-token")
        raise ArgumentError, "Request credential changed" unless Digest::SHA256.hexdigest(token) == r.credential_digest

        # The session-scoped file is the Controller's current request
        # capability; replace it for each dispatched request.
        session_token = "#{s.id}.request-token"
        @credentials.delete(name: session_token)
        @credentials.write(name: session_token, token: token)
        @requests.mark(id: r.id, state: State::Uncertain)
        raise IOError, "Dispatch lease lost" unless lease.begin_effect

        @herdr.prompt(pane_id: s.pane_id, text: prompt(r, d))
        @requests.mark(id: r.id, state: State::Active)
        Decision.complete
      end

      sig { params(old: Request).void }
      private def expire(old)
        @requests.mark(id: old.id, state: State::Uncertain, reason: "Expired; human reconciliation required")
        old_source = T.must(@inbox.find(id: old.inbox_id))
        message = Messaging::Dto::OutgoingMessage.new(
          channel_id: old_source.channel_id,
          thread_id: old_source.thread_id,
          bot: Messaging::Dto::Bot::Agent,
          role: Messaging::Dto::SpeakerRole::Controller,
          body: "Master request #{old.id} expired without a completion receipt. Verify its outcome, then use @agent recover-master #{old.id} to continue the same session.",
          key: "master:expired:#{old.id}"
        )
        Platform::Unwrap.call(@outbox.enqueue(message: message))
      end

      sig { params(r: Request, d: Messaging::Dto::VerifiedDelivery).returns(String) }
      private def prompt(r, d)
        "Verified human request #{r.id} from channel #{d.channel_id}, thread #{d.thread_id}: #{d.body}\nUse typed MCP tools with request_id #{r.id}. " \
          "Inspect authoritative projects/workflows and relevant conversation context. " \
          "Reuse the matching existing conversation; ask a concise clarification for multiple plausible matches. " \
          "Do not invent new sessions for follow-ups. " \
          "Report completion with master-reply for this exact request."
      end

      sig { params(session_id: String).returns(T.nilable(Domains::Sessions::Dto::SessionView)) }
      private def active_controller(session_id)
        session = @registry.find(id: session_id)
        session if session&.active && session.role == Domains::Sessions::Dto::SessionRole::Controller
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(String) }
      private def request_id(job)
        value = Domains::Commander::Dto::MasterDispatchJob.from_hash(job.payload, true).request_id
        raise ArgumentError, "Master job is malformed" unless value.match?(/\A[0-9a-f-]+\z/)

        value
      end
    end
  end
end
