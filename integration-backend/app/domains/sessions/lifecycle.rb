# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    class Lifecycle
      extend T::Sig

      Status = Adapters::Herdr::Dto::AgentStatus
      SETTLED = T.let([Status::Idle, Status::Done].freeze, T::Array[Adapters::Herdr::Dto::AgentStatus])
      RENEWABLE = T.let([Status::Idle, Status::Working, Status::Done].freeze, T::Array[Adapters::Herdr::Dto::AgentStatus])

      JsonObject = T.type_alias { T::Hash[String, Object] }
      Row = T.type_alias { T::Hash[Symbol, Object] }
      Configuration = T.type_alias { T::Hash[String, Object] }

      sig do
        params(
          db: Sequel::Database,
          herdr: Adapters::Herdr::Client,
          source: Domains::Commander::Source,
          callback_url: String,
          credential_root: String,
          policy: Domains::Workflows::Policy
        ).void
      end
      def initialize(db, herdr:, source:, callback_url:, credential_root: "/run/herdr/session-credentials", policy: Domains::Workflows::Policy.new)
        @db = db
        @herdr = herdr
        @source = source
        @credentials = T.let(Adapters::Credentials::FileStore.new(root: credential_root), Adapters::Credentials::FileStore)
        @url = callback_url
        @policy = policy
        @lock = T.let(Platform::Lock.new, Platform::Lock)
      end

      # Called only by operator-configured bootstrap; never exposed as an MCP
      # tool to Worker/Reviewer or accepted from a model-supplied role.
      sig { params(configuration: Configuration).returns(String) }
      def bootstrap(configuration:)
        @lock.call(key: "controller") do
          existing = @db[:sessions][role: "controller", active: true]
          if existing
            queue_renewal(existing) if existing[:credential_expires_at] <= Time.now + 300
            return existing[:id]
          end

          pending = @db[:sessions].where(role: "controller").join(:session_operations, session_id: :id).where(Sequel[:session_operations][:kind] => "start", Sequel[:session_operations][:state] => %w[queued sending uncertain]).select(Sequel[:sessions][:id]).first
          return pending[:id] if pending

          validate_configuration!(configuration)
          id, token = SecureRandom.uuid, SecureRandom.hex(32)
          @credentials.write(name: credential_name(id), token: token)
          @db.transaction do
            generation = (@db[:sessions].where(role: "controller").max(:generation) || 0) + 1
            @db[:sessions].insert(id: id, role: "controller", generation: generation, pane_id: "pending:#{id}", alias: "digitaltwin-#{id}",
                                  configuration: Sequel.pg_jsonb(configuration), credential_digest: Digest::SHA256.hexdigest(token), credential_expires_at: Time.now + 3600, active: false)
            op = SecureRandom.uuid
            @db[:session_operations].insert(id: op, session_id: id, kind: "start")
            Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::SessionStart, payload: Dto::SessionOperationJob.new(operation_id: op), dispatch_key: "session:start:#{id}")
          end
          id
        end
      end

      sig { params(workflow_id: String, role: String).returns(String) }
      def reserve(workflow_id:, role:)
        raise ArgumentError, "Workflow role required" unless %w[writer reviewer].include?(role)

        w = @db[:workflows][id: workflow_id] or raise ArgumentError, "Missing workflow"
        @source.human(w[:source_inbox_id], destination: w[:channel_id])
        @lock.call(key: workflow_id) do
          existing = @db[:sessions][workflow_id: workflow_id, role: role, active: true]
          if existing
            queue_renewal(existing) if existing[:credential_expires_at] <= Time.now + 300
            return existing[:id]
          end

          queued = @db[:sessions].where(workflow_id: workflow_id, role: role).join(:session_operations, session_id: :id).where(Sequel[:session_operations][:kind] => "start", Sequel[:session_operations][:state] => %w[queued sending uncertain]).select(Sequel[:sessions][:id]).first
          return queued[:id] if queued

          configuration = w[:role_configurations].fetch(role)
          validate_configuration!(configuration)
          id = SecureRandom.uuid
          token = SecureRandom.hex(32)
          @credentials.write(name: credential_name(id), token: token)
          @db.transaction do
            generation = (@db[:sessions].where(workflow_id: workflow_id, role: role).max(:generation) || 0) + 1
            @db[:sessions].insert(id: id, workflow_id: workflow_id, role: role, generation: generation, pane_id: "pending:#{id}", alias: "digitaltwin-#{id}",
                                  configuration: Sequel.pg_jsonb(configuration), credential_digest: Digest::SHA256.hexdigest(token), credential_expires_at: Time.now + 3600, active: false)
            op = SecureRandom.uuid
            @db[:session_operations].insert(id: op, session_id: id, kind: "start")
            Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::SessionStart, payload: Dto::SessionOperationJob.new(operation_id: op), dispatch_key: "session:start:#{id}")
            Domains::Mattermost::Outbox.new.enqueue(channel_id: w[:channel_id], thread_id: w[:thread_id], bot: "worker", role: role,
                                                    body: "#{role.capitalize} session #{id} reserved; start operation #{op} is queued, not started.", key: "session:reserved:#{id}")
          end
          id
        end
      end

      sig { params(operation_id: String, before_effect: T.proc.returns(T::Boolean)).returns(String) }
      def execute(operation_id, before_effect: -> { true })
        op = @db[:session_operations][id: operation_id] or raise ArgumentError, "Missing session operation"
        session = @db[:sessions][id: op[:session_id]]
        @lock.call(key: session[:workflow_id] || "controller") do
          op = @db[:session_operations][id: operation_id]
          return op[:state] unless op[:state] == "queued"
          return "queued" unless @policy.dispatch_allowed?

          w = @db[:workflows][id: session[:workflow_id]]
          @source.human(w[:source_inbox_id], destination: w[:channel_id]) if w
          if op[:kind] == "start"
            return "queued" if w && (w[:phase] == "paused" || w[:archived_at] || %w[closed cancelled].include?(w[:phase]))
          end
          @db[:session_operations].where(id: operation_id).update(state: "sending")
          begin
            raise IOError, "Dispatch lease lost" unless before_effect.call

            if op[:kind] == "start"
              env = { "DIGITALTWIN_SESSION_TOKEN_FILE" => @credentials.path(name: credential_name(session[:id])), "DIGITALTWIN_SESSION_GENERATION" => session[:generation].to_s, "DIGITALTWIN_CALLBACK_URL" => @url,
                      "DIGITALTWIN_MASTER_REQUEST_TOKEN_FILE" => @credentials.path(name: "#{session[:id]}.request-token") }
              created = @herdr.create_workspace(cwd: w ? w[:worktree_path] : nil, label: session[:alias], env: env)
              @db[:sessions].where(id: session[:id]).update(pane_id: created.root_pane_id, workspace_id: created.workspace_id)
              live = @herdr.start(pane_id: created.root_pane_id, name: session[:alias], launch: launch_spec(session[:configuration]))
              identity = live.agent_session
              raise IOError, "Unproved conversation identity" unless identity && proven_identity?(identity)

              @db.transaction do
                @db[:sessions].where(id: session[:id]).update(active: true, runtime_identity: Sequel.pg_jsonb(identity.serialize), state: live.agent_status.serialize, last_verified_at: Time.now)
                complete_operation(op, session, w)
              end
            else
              live = @herdr.pane(session[:pane_id])
              raise IOError, "Uncertain or replaced session" unless live.agent_session&.serialize == session[:runtime_identity] && SETTLED.include?(live.agent_status)

              @herdr.close(pane_id: session[:pane_id])
              @db.transaction do
                @db[:sessions].where(id: session[:id]).update(active: false, state: "done")
                complete_operation(op, session, w)
              end
              @credentials.delete(name: credential_name(session[:id]))
            end
            "complete"
          rescue StandardError
            @db[:session_operations].where(id: operation_id).update(state: "uncertain", reason: "Runtime effect requires reconciliation; do not repeat")
            "uncertain"
          end
        end
      end

      private

      sig { params(op: Row, session: Row, workflow: T.nilable(Row)).void }
      def complete_operation(op, session, workflow)
        @db[:session_operations].where(id: op[:id]).update(state: "complete")
        queue_renewal(@db[:sessions][id: session[:id]]) if op[:kind] == "start"
        if workflow && row_string(op, :kind) == "start" && row_string(session, :role) == "writer"
          workflow_id = row_string(workflow, :id)
          version = row_integer(workflow, :version)
          Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::WorkflowPhasePrompt, payload: Domains::Workflows::Dto::PhasePromptJob.new(workflow_id: workflow_id, version: version),
                                            dispatch_key: "workflow:phase:#{workflow_id}:#{version}")
        elsif workflow && row_string(op, :kind) == "stop" && %w[closed cancelled].include?(row_string(workflow, :phase)) && @db[:sessions].where(workflow_id: row_string(workflow, :id), active: true).empty?
          @db[:workflows].where(id: row_string(workflow, :id)).update(archived_at: Time.now)
        end
      end

      sig { params(session: Row).returns(String) }
      def queue_renewal(session) = self.class.schedule_renewal(@db, session)

      class << self
        extend T::Sig

        sig { params(_db: Sequel::Database, session: Row).returns(String) }
        def schedule_renewal(_db, session)
          id = row_string(session, :id)
          expires_at = row_time(session, :credential_expires_at)
          key = "session:renew:#{id}:#{expires_at.to_i}"
          Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::SessionRenew, payload: Dto::RenewalJob.new(session_id: id, generation: row_integer(session, :generation)),
                                            dispatch_key: key, available_at: [Time.now, expires_at - 300].max)
        end
      end

      public

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def renew_job(job:)
        return Platform::Jobs::Dto::Decision.block("Live session renewal evidence required") unless @policy.dispatch_allowed?

        payload = Dto::RenewalJob.from_hash(job.payload, true)
        renew(session_id: payload.session_id, generation: payload.generation)
        Platform::Jobs::Dto::Decision.complete
      end

      sig { params(session_id: String, generation: Integer).void }
      def renew(session_id:, generation:)
        s = @db[:sessions][id: session_id, generation: generation, active: true] or raise ArgumentError, "Inactive renewal session"
        @lock.call(key: s[:workflow_id] || "controller") do
          s = @db[:sessions][id: session_id, generation: generation, active: true] or raise ArgumentError, "Inactive renewal session"
          scope = s[:workflow_id] ? { workflow_id: s[:workflow_id], role: s[:role] } : { role: "controller" }
          raise ArgumentError, "Session replaced" unless @db[:sessions].where(scope).max(:generation) == generation

          w = s[:workflow_id] && @db[:workflows][id: s[:workflow_id]]
          @source.human(w[:source_inbox_id], destination: w[:channel_id]) if w
          live = @herdr.pane(s[:pane_id])
          raise ArgumentError, "Session identity not proven" unless s[:runtime_identity] && live.agent_session&.serialize == s[:runtime_identity] && RENEWABLE.include?(live.agent_status)

          token = @credentials.read(name: credential_name(s[:id]))
          raise ArgumentError, "Credential changed" unless Digest::SHA256.hexdigest(token) == s[:credential_digest]

          @db.transaction do
            @db[:sessions].where(id: s[:id]).update(credential_expires_at: Time.now + 3600, last_verified_at: Time.now)
            queue_renewal(@db[:sessions][id: s[:id]])
          end
        end
      end

      sig { void }
      def renew_due
        @db[:sessions].where(active: true).each { |s| queue_renewal(s) }
      end

      sig { params(operation_id: String, inbox_id: Integer, pane_id: String).returns(String) }
      def reconcile(operation_id:, inbox_id:, pane_id:)
        op = @db[:session_operations][id: operation_id] or raise ArgumentError, "Unknown session operation"
        s = @db[:sessions][id: op[:session_id]]
        w = s[:workflow_id] && @db[:workflows][id: s[:workflow_id]]
        initial_request = !w && @db[:master_requests].where(session_id: s[:id]).order(:inbox_id).first
        original_id = w ? w[:source_inbox_id] : initial_request && initial_request[:inbox_id]
        original = original_id && @db[:inbox][id: original_id]
        raise ArgumentError, "Human source binding required" unless original

        d = @source.human(inbox_id, destination: w ? w[:channel_id] : original[:channel_id])
        command = "@#{ENV.fetch("AGENT_HANDLE", "agent")} recover-session #{operation_id} #{pane_id}"
        raise ArgumentError, "Exact original-human session recovery required" unless d.actor.user_id == original[:user_id] && d.body == command

        @lock.call(key: w ? w[:id] : "controller") do
          op = @db[:session_operations][id: operation_id]
          key = "session:recovery:#{operation_id}"
          audit = Platform::Audit::Log.new
          jobs = Platform::Jobs::Store.new
          receipt = audit.find(event_key: key)
          if receipt
            raise ArgumentError, "Recovery pane changed" unless Dto::SessionRecoveryAudit.from_hash(receipt.details, true).pane_id == pane_id

            return "complete"
          end
          raise ArgumentError, "Operation not uncertain" unless %w[sending uncertain].include?(op[:state])

          s = @db[:sessions][id: s[:id]]
          raise ArgumentError, "Session generation replaced" unless @db[:sessions].where(w ? { workflow_id: w[:id], role: s[:role] } : { role: "controller" }).max(:generation) == s[:generation]
          raise ArgumentError, "Different recorded pane" unless s[:pane_id].start_with?("pending:") || s[:pane_id] == pane_id

          job = jobs.find_by_key(dispatch_key: "session:#{op[:kind]}:#{s[:id]}")
          lease_expires_at = job&.lease_expires_at
          raise ArgumentError, "Operation lease still live" if job&.status == Platform::Jobs::Dto::JobStatus::Running && lease_expires_at && lease_expires_at > Time.now

          changes = if op[:kind] == "start"
                      raise ArgumentError, "Workflow closed" if w && (w[:archived_at] || %w[closed cancelled].include?(w[:phase]))

                      live = @herdr.pane(pane_id)
                      identity = live.agent_session
                      raise ArgumentError, "Unproved exact role conversation" unless identity && proven_identity?(identity)

                      valid = live.name == s[:alias] && live.cwd == (w ? w[:worktree_path] : "/home/runtime") && live.agent == s[:configuration]["cli"] && identity.agent == s[:configuration]["cli"]
                      valid &&= SETTLED.include?(live.agent_status) && live.interactive_ready == true && live.launch_pending == false
                      raise ArgumentError, "Unproved exact role conversation" unless valid

                      token = @credentials.read(name: credential_name(s[:id]))
                      raise ArgumentError, "Credential changed" unless Digest::SHA256.hexdigest(token) == s[:credential_digest]

                      { pane_id: pane_id, active: true, runtime_identity: Sequel.pg_jsonb(identity.serialize), state: live.agent_status.serialize, credential_expires_at: Time.now + 3600, last_verified_at: Time.now }
                    else
                      raise ArgumentError, "Stop pane mismatch" unless s[:pane_id] == pane_id
                      raise ArgumentError, "Recorded pane still exists" if @herdr.panes.any? { |pane| pane.pane_id == pane_id }

                      { active: false, state: "done" }
                    end
          @db.transaction do
            @db[:sessions].where(id: s[:id]).update(changes)
            complete_operation(op, s, w && @db[:workflows][id: w[:id]])
            jobs.close_reconciled(id: job.id) if job
            details = Dto::SessionRecoveryAudit.new(inbox_id: inbox_id, operation_id: operation_id, session_id: s[:id], generation: s[:generation], pane_id: pane_id)
            audit.record(event_key: key, action: "verified_session_reconciliation", details: details)
            Domains::Mattermost::Outbox.new.enqueue(channel_id: d.channel_id, thread_id: d.thread_id, bot: "agent", role: "controller", body: "Session operation #{operation_id} reconciled against runtime evidence; no start or stop was repeated.", key: key)
          end
          @credentials.delete(name: credential_name(s[:id])) if op[:kind] == "stop"
          "complete"
        end
      end

      sig { params(workflow_id: String).void }
      def stop(workflow_id:)
        @lock.call(key: workflow_id) do
          @db.transaction do
            @db[:sessions].where(workflow_id: workflow_id, active: true).each do |s|
              next if @db[:session_operations][session_id: s[:id], kind: "stop"]

              op = SecureRandom.uuid
              @db[:session_operations].insert(id: op, session_id: s[:id], kind: "stop")
              Platform::Jobs::Store.new.enqueue(kind: Platform::Jobs::Dto::JobKind::SessionStop, payload: Dto::SessionOperationJob.new(operation_id: op), dispatch_key: "session:stop:#{s[:id]}")
            end
          end
        end
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        state = execute(Dto::SessionOperationJob.from_hash(job.payload, true).operation_id, before_effect: -> { job.lease.begin_effect })
        if state == "queued" && @policy.dispatch_allowed?
          Platform::Jobs::Dto::Decision.defer("Session start waits for phase")
        elsif state != "complete"
          Platform::Jobs::Dto::Decision.block("Session #{state}; evidence/reconciliation required")
        else
          Platform::Jobs::Dto::Decision.complete
        end
      end

      private

      sig { params(config: Configuration).void }
      def validate_configuration!(config)
        required = %w[cli provider model family]
        required.each do |key|
          value = config[key]
          raise ArgumentError, "Incomplete role configuration" unless value.is_a?(String) && !value.empty?
        end

        args = config["launch_args"]
        raise ArgumentError, "Incomplete role configuration" unless args.is_a?(Array)

        args.each do |argument|
          raise ArgumentError, "Incomplete role configuration" unless argument.is_a?(String) && !argument.include?("\0")
        end
      end
      sig { params(id: String).returns(String) }
      def credential_name(id) = "#{id}.token"

      sig { params(identity: Adapters::Herdr::Dto::AgentSession).returns(T::Boolean) }
      def proven_identity?(identity)
        [identity.source, identity.agent, identity.kind, identity.value].none?(&:empty?)
      end

      # Sequel returns the JSONB configuration as a Delegator, which is not an
      # Object. validate_configuration! already checked it at reservation.
      sig { params(value: BasicObject).returns(Adapters::Herdr::Dto::LaunchSpec) }
      def launch_spec(value)
        configuration = Sequel::Postgres::JSONBHash === value ? value.to_hash : Hash.try_convert(value)
        raise IOError, "Invalid Herdr configuration" unless configuration

        cli = configuration["cli"]
        args = configuration["launch_args"]
        raise IOError, "Invalid Herdr configuration" unless cli.is_a?(String) && args.is_a?(Array) && args.all? { |argument| argument.is_a?(String) }

        Adapters::Herdr::Dto::LaunchSpec.new(cli: cli, launch_args: args)
      end

      class << self
        extend T::Sig

        sig { params(row: Row, key: Symbol).returns(String) }
        def row_string(row, key)
          value = row.fetch(key) { raise ArgumentError, "Malformed database row" }
          raise ArgumentError, "Malformed database row" unless value.is_a?(String)

          value
        end

        sig { params(row: Row, key: Symbol).returns(Integer) }
        def row_integer(row, key)
          value = row.fetch(key) { raise ArgumentError, "Malformed database row" }
          raise ArgumentError, "Malformed database row" unless value.is_a?(Integer)

          value
        end

        sig { params(row: Row, key: Symbol).returns(Time) }
        def row_time(row, key)
          value = row.fetch(key) { raise ArgumentError, "Malformed database row" }
          raise ArgumentError, "Malformed database row" unless value.is_a?(Time)

          value
        end
      end

      sig { params(row: Row, key: Symbol).returns(String) }
      def row_string(row, key) = self.class.row_string(row, key)

      sig { params(row: Row, key: Symbol).returns(Integer) }
      def row_integer(row, key) = self.class.row_integer(row, key)
    end
  end
end
