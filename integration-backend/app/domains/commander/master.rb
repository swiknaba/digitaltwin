# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    class Master
      extend T::Sig

      Status = Adapters::Herdr::Dto::AgentStatus
      Identity = Adapters::Herdr::ConversationIdentity

      sig do
        params(db: Sequel::Database, bootstrap: ::Services::Sessions::BootstrapController, source: Domains::Messaging::VerifyHumanSource,
               herdr: Adapters::Herdr::Client, configuration: Domains::Workflows::Dto::RoleConfig,
               credential_root: String, policy: Domains::Workflows::Policy, registry: Domains::Sessions::Registry,
               operations: Domains::Sessions::Operations).void
      end
      def initialize(db, bootstrap:, source:, herdr:, configuration:, credential_root: "/run/herdr/session-credentials", policy: Domains::Workflows::Policy.new,
                     registry: Domains::Sessions::Registry.new, operations: Domains::Sessions::Operations.new)
        @db = db
        @bootstrap = bootstrap
        @registry = registry
        @operations = operations
        @source = source
        @herdr = herdr
        @configuration = configuration
        @credentials = T.let(Adapters::Credentials::FileStore.new(root: credential_root), Adapters::Credentials::FileStore)
        @policy = policy
        @inbox = T.let(Domains::Messaging::Inbox.new, Domains::Messaging::Inbox)
      end

      sig { params(inbox_id: String).returns(String) }
      def ingest(inbox_id)
        d = Platform::Unwrap.call(@source.call(inbox_id: inbox_id))
        controller = Platform::Unwrap.call(@bootstrap.call(configuration: @configuration))
        @db.transaction do
          @inbox.lock(id: inbox_id)
          old = @db[:master_requests][inbox_id: inbox_id]
          return old[:id] if old

          id, token = SecureRandom.uuid, SecureRandom.hex(32)
          @credentials.write(name: "#{id}.request-token", token: token)
          @db[:master_requests].insert(id: id, inbox_id: inbox_id, session_id: controller, credential_digest: Digest::SHA256.hexdigest(token), expires_at: Time.now + 1800)
          Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::MasterDispatch, payload: Dto::MasterDispatchJob.new(request_id: id), dispatch_key: "master:dispatch:#{id}")
          message = Domains::Messaging::Dto::OutgoingMessage.new(
            channel_id: d.channel_id,
            thread_id: d.thread_id,
            bot: Domains::Messaging::Dto::Bot::Agent,
            role: Domains::Messaging::Dto::SpeakerRole::Controller,
            body: "Request #{id} queued for Master; delivery pending. Session #{controller}, start operation #{@operations.for_session(session_id: controller, kind: Domains::Sessions::Dto::OperationKind::Start)&.id}.",
            key: "master:queued:#{id}"
          )
          Platform::Unwrap.call(Domains::Messaging::Outbox.new.enqueue(message: message))
          id
        end
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        r = @db[:master_requests][id: request_id(job)]
        Platform::Lock.new.call(key: "controller") do
          r = @db[:master_requests][id: r[:id]]
          return Platform::Jobs::Dto::Decision.complete if r[:state] == "active" || r[:state] == "complete"
          raise ArgumentError, "Master request uncertain" unless r[:state] == "queued"

          return Platform::Jobs::Dto::Decision.block("Selected Master CLI/MCP live evidence required") unless @policy.dispatch_allowed?

          expired = @db[:master_requests].where(session_id: r[:session_id], state: "active").where(Sequel[:master_requests][:expires_at] <= Time.now).all
          expired.each do |old|
            @db[:master_requests].where(id: old[:id]).update(state: "uncertain", reason: "Expired; human reconciliation required")
            old_source = T.must(@inbox.find(id: old[:inbox_id]))
            message = Domains::Messaging::Dto::OutgoingMessage.new(
              channel_id: old_source.channel_id,
              thread_id: old_source.thread_id,
              bot: Domains::Messaging::Dto::Bot::Agent,
              role: Domains::Messaging::Dto::SpeakerRole::Controller,
              body: "Master request #{old[:id]} expired without a completion receipt. Verify its outcome, then use @agent recover-master #{old[:id]} to continue the same session.",
              key: "master:expired:#{old[:id]}"
            )
            Platform::Unwrap.call(Domains::Messaging::Outbox.new.enqueue(message: message))
          end
          uncertain = @db[:master_requests].where(session_id: r[:session_id], state: "uncertain").exclude(id: r[:id]).count
          return Platform::Jobs::Dto::Decision.block("Prior Master request requires human reconciliation") if uncertain.positive?

          busy = @db[:master_requests].where(session_id: r[:session_id], state: %w[active uncertain]).exclude(id: r[:id]).count
          s = active_session(r[:session_id])
          s = nil unless s&.role == Domains::Sessions::Dto::SessionRole::Controller
          return Platform::Jobs::Dto::Decision.defer("Master startup or current request pending") if !s || busy.positive?

          raise ArgumentError, "Master request/session expired" unless r[:expires_at] > Time.now && s.credential_expires_at > Time.now

          d = Platform::Unwrap.call(@source.call(inbox_id: r[:inbox_id]))
          live = @herdr.pane(s.pane_id)
          same_conversation = Identity.same?(s.runtime_identity, live.agent_session)
          if same_conversation && live.agent_status == Status::Working
            return Platform::Jobs::Dto::Decision.defer("Master finishing current turn")
          end
          raise ArgumentError, "Master conversation replaced or uncertain" unless same_conversation && live.agent_status.settled?

          token = @credentials.read(name: "#{r[:id]}.request-token")
          raise ArgumentError, "Request credential changed" unless Digest::SHA256.hexdigest(token) == r[:credential_digest]

          # The session-scoped file is the Controller's current request
          # capability; replace it for each dispatched request.
          session_token = "#{s.id}.request-token"
          @credentials.delete(name: session_token)
          @credentials.write(name: session_token, token: token)
          @db[:master_requests].where(id: r[:id]).update(state: "uncertain")
          raise IOError, "Dispatch lease lost" unless job.lease.begin_effect

          prompt = "Verified human request #{r[:id]} from channel #{d.channel_id}, thread #{d.thread_id}: #{d.body}\nUse typed MCP tools with request_id #{r[:id]}. " \
                   "Inspect authoritative projects/workflows and relevant conversation context. " \
                   "Reuse the matching existing conversation; ask a concise clarification for multiple plausible matches. " \
                   "Do not invent new sessions for follow-ups. " \
                   "Report completion with master-reply for this exact request."
          @herdr.prompt(pane_id: s.pane_id, text: prompt)
          @db[:master_requests].where(id: r[:id]).update(state: "active")
          Platform::Jobs::Dto::Decision.complete
        end
      end

      sig { params(request_id: String, inbox_id: String).void }
      def recover(request_id:, inbox_id:)
        r = @db[:master_requests][id: request_id] or raise ArgumentError, "Unknown Master request"
        original = T.must(@inbox.find(id: r[:inbox_id]))
        d = Platform::Unwrap.call(@source.call(inbox_id: inbox_id, destination: original.channel_id))
        raise ArgumentError, "Recovery requires the original human's exact request binding" unless d.actor.user_id == original.user_id && d.body == "@#{ENV.fetch("AGENT_HANDLE", "agent")} recover-master #{request_id}"

        Platform::Lock.new.call(key: "controller") do
          raise ArgumentError, "Request does not require recovery" unless @db[:master_requests][id: request_id][:state] == "uncertain"

          wids = Domains::Workflows::Catalog.new.ids_for_source(inbox_id: original.id)
          start = Domains::Workflows::Requests.new.for_inbox(inbox_id: original.id)
          start_uncertain = start && [Domains::Workflows::Dto::RequestState::Sending, Domains::Workflows::Dto::RequestState::Uncertain].include?(start.state)
          raise ArgumentError, "Workflow effect still uncertain" if start_uncertain || @db[:reviews].where(workflow_id: wids, dispatch_state: %w[sending uncertain]).count.positive?

          raise ArgumentError, "Session effect still uncertain" if @operations.unsettled_in_workflows?(workflow_ids: wids)

          s = active_session(r[:session_id])
          live = s && @herdr.pane(s.pane_id)
          raise ArgumentError, "Master session not positively settled" unless s && live && Identity.same?(s.runtime_identity, live.agent_session) && live.agent_status.settled?

          jobs = Platform::Jobs::Store.new
          @db.transaction do
            @db[:master_requests].where(id: request_id).update(state: "complete", reason: "Recovered by verified human source #{inbox_id}")
            @db[:master_requests].where(session_id: r[:session_id], state: "queued").each do |queued|
              job = jobs.find_by_key(dispatch_key: "master:dispatch:#{queued[:id]}")
              jobs.requeue_blocked(id: job.id) if job
            end
          end
        end
      end

      sig { params(request_id: String, token: String, text: String).returns(String) }
      def reply(request_id:, token:, text:)
        r = Requests.new(@db, source: @source).authorize(request_id, token, states: %w[active complete])
        raise ArgumentError, "Invalid Master reply" unless text.bytesize.between?(1, 60_000)

        Platform::Lock.new.call(key: "controller") do
          @db.transaction do
            row = @db[:master_requests].where(id: r[:id]).for_update.first
            if row[:state] == "complete"
              receipt = Domains::Messaging::Outbox.new.item_by_key(key: "master:reply:#{r[:id]}")
              raise ArgumentError, "Changed or recovered reply" unless receipt && receipt.body == text

              return "queued"
            end
            raise ArgumentError, "Request already completed" unless row[:state] == "active"

            source = T.must(@inbox.find(id: row[:inbox_id]))
            message = Domains::Messaging::Dto::OutgoingMessage.new(
              channel_id: source.channel_id,
              thread_id: source.thread_id,
              bot: Domains::Messaging::Dto::Bot::Agent,
              role: Domains::Messaging::Dto::SpeakerRole::Controller,
              body: text,
              key: "master:reply:#{r[:id]}"
            )
            Platform::Unwrap.call(Domains::Messaging::Outbox.new.enqueue(message: message))
            @db[:master_requests].where(id: r[:id]).update(state: "complete")
            "queued"
          end
        end
      end

      # master_requests rows are untyped until Task 9; only a String id names a session.
      sig { params(session_id: BasicObject).returns(T.nilable(Domains::Sessions::Dto::SessionView)) }
      private def active_session(session_id)
        session = case session_id
                  when String then @registry.find(id: session_id)
                  end
        session if session&.active
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(String) }
      private def request_id(job)
        value = Dto::MasterDispatchJob.from_hash(job.payload, true).request_id
        raise ArgumentError, "Master job is malformed" unless value.match?(/\A[0-9a-f-]+\z/)

        value
      end
    end
  end
end
