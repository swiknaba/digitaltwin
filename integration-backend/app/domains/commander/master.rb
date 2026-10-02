# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    class Master
      extend T::Sig

      sig do
        params(db: Sequel::Database, sessions: Domains::Sessions::Lifecycle, source: Source,
               herdr: Domains::Sessions::Herdr, configuration: Domains::Sessions::Lifecycle::Configuration,
               credential_root: String, policy: Domains::Workflows::Policy).void
      end
      def initialize(db, sessions:, source:, herdr:, configuration:, credential_root: "/run/herdr/session-credentials", policy: Domains::Workflows::Policy.new)
        @db = db
        @sessions = sessions
        @source = source
        @herdr = herdr
        @configuration = configuration
        @root = credential_root
        @policy = policy
      end

      sig { params(inbox_id: T.any(Integer, String)).returns(String) }
      def ingest(inbox_id)
        d = @source.human(inbox_id)
        controller = @sessions.bootstrap(configuration: @configuration)
        @db.transaction do
          @db[:inbox].where(id: inbox_id).for_update.first
          old = @db[:master_requests][inbox_id: inbox_id]
          return old[:id] if old

          id, token = SecureRandom.uuid, SecureRandom.hex(32)
          FileUtils.mkdir_p(@root, mode: 0700)
          File.open(File.join(@root, "#{id}.request-token"), File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(token) }
          @db[:master_requests].insert(id: id, inbox_id: inbox_id, session_id: controller, credential_digest: Digest::SHA256.hexdigest(token), expires_at: Time.now + 1800)
          Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::MasterDispatch, payload: Dto::MasterDispatchJob.new(request_id: id), dispatch_key: "master:dispatch:#{id}")
          Domains::Mattermost::Outbox.new.enqueue(channel_id: d.channel_id, thread_id: d.thread_id, bot: "agent", role: "controller",
                                                  body: "Request #{id} queued for Master; delivery pending. Session #{controller}, start operation #{@db[:session_operations][session_id: controller, kind: "start"]&.dig(:id)}.", key: "master:queued:#{id}")
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
            old_source = @db[:inbox][id: old[:inbox_id]]
            Domains::Mattermost::Outbox.new.enqueue(channel_id: old_source[:channel_id], thread_id: old_source[:thread_id], bot: "agent", role: "controller",
                                                    body: "Master request #{old[:id]} expired without a completion receipt. Verify its outcome, then use @agent recover-master #{old[:id]} to continue the same session.", key: "master:expired:#{old[:id]}")
          end
          uncertain = @db[:master_requests].where(session_id: r[:session_id], state: "uncertain").exclude(id: r[:id]).count
          return Platform::Jobs::Dto::Decision.block("Prior Master request requires human reconciliation") if uncertain.positive?

          busy = @db[:master_requests].where(session_id: r[:session_id], state: %w[active uncertain]).exclude(id: r[:id]).count
          s = @db[:sessions][id: r[:session_id], active: true, role: "controller"]
          return Platform::Jobs::Dto::Decision.defer("Master startup or current request pending") if !s || busy.positive?

          raise ArgumentError, "Master request/session expired" unless r[:expires_at] > Time.now && s[:credential_expires_at] > Time.now

          d = @source.human(r[:inbox_id])
          live = @herdr.get(s[:pane_id])
          if s[:runtime_identity] && live["agent_session"] == s[:runtime_identity] && live["agent_status"] == "working"
            return Platform::Jobs::Dto::Decision.defer("Master finishing current turn")
          end
          raise ArgumentError, "Master conversation replaced or uncertain" unless s[:runtime_identity] && live["agent_session"] == s[:runtime_identity] && %w[idle done].include?(live["agent_status"])

          token = File.read(File.join(@root, "#{r[:id]}.request-token"))
          raise ArgumentError, "Request credential changed" unless Digest::SHA256.hexdigest(token) == r[:credential_digest]

          path = File.join(@root, "#{s[:id]}.request-token")
          File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0600) { |file| file.write(token) }
          @db[:master_requests].where(id: r[:id]).update(state: "uncertain")
          raise IOError, "Dispatch lease lost" unless job.lease.begin_effect

          prompt = "Verified human request #{r[:id]} from channel #{d.channel_id}, thread #{d.thread_id}: #{d.body}\nUse typed MCP tools with request_id #{r[:id]}. " \
                   "Inspect authoritative projects/workflows and relevant conversation context. " \
                   "Reuse the matching existing conversation; ask a concise clarification for multiple plausible matches. " \
                   "Do not invent new sessions for follow-ups. " \
                   "Report completion with master-reply for this exact request."
          @herdr.prompt(s[:pane_id], prompt)
          @db[:master_requests].where(id: r[:id]).update(state: "active")
          Platform::Jobs::Dto::Decision.complete
        end
      end

      sig { params(request_id: String, inbox_id: T.any(Integer, String)).void }
      def recover(request_id:, inbox_id:)
        r = @db[:master_requests][id: request_id] or raise ArgumentError, "Unknown Master request"
        original = @db[:inbox][id: r[:inbox_id]]
        d = @source.human(inbox_id, destination: original[:channel_id])
        raise ArgumentError, "Recovery requires the original human's exact request binding" unless d.actor.user_id == original[:user_id] && d.body == "@#{ENV.fetch("AGENT_HANDLE", "agent")} recover-master #{request_id}"

        Platform::Lock.new.call(key: "controller") do
          raise ArgumentError, "Request does not require recovery" unless @db[:master_requests][id: request_id][:state] == "uncertain"

          wids = @db[:workflows].where(source_inbox_id: r[:inbox_id]).select_map(:id)
          raise ArgumentError, "Workflow effect still uncertain" if @db[:workflow_requests].where(inbox_id: r[:inbox_id], state: %w[sending uncertain]).count.positive? || @db[:reviews].where(workflow_id: wids, dispatch_state: %w[sending uncertain]).count.positive?

          sids = @db[:sessions].where(workflow_id: wids).select_map(:id)
          raise ArgumentError, "Session effect still uncertain" if @db[:session_operations].where(session_id: sids, state: %w[sending uncertain]).count.positive?

          s = @db[:sessions][id: r[:session_id], active: true]
          live = s && @herdr.get(s[:pane_id])
          raise ArgumentError, "Master session not positively settled" unless live && s[:runtime_identity] && live["agent_session"] == s[:runtime_identity] && %w[idle done].include?(live["agent_status"])

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
              receipt = @db[:outbox][response_key: "master:reply:#{r[:id]}"]
              raise ArgumentError, "Changed or recovered reply" unless receipt && receipt[:body] == text

              return "queued"
            end
            raise ArgumentError, "Request already completed" unless row[:state] == "active"

            source = @db[:inbox][id: r[:inbox_id]]
            Domains::Mattermost::Outbox.new.enqueue(channel_id: source[:channel_id], thread_id: source[:thread_id], bot: "agent", role: "controller", body: text, key: "master:reply:#{r[:id]}")
            @db[:master_requests].where(id: r[:id]).update(state: "complete")
            "queued"
          end
        end
      end

      private

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(String) }
      def request_id(job)
        value = Dto::MasterDispatchJob.from_hash(job.payload, true).request_id
        raise ArgumentError, "Master job is malformed" unless value.match?(/\A[0-9a-f-]+\z/)

        value
      end
    end
  end
end
