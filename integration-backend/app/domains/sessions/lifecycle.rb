# typed: strict
# frozen_string_literal: true

require "digest"
require "fileutils"
module Domains
  module Sessions
    class Lifecycle
      extend T::Sig

      JsonObject = T.type_alias { T::Hash[String, Object] }
      Row = T.type_alias { T::Hash[Symbol, Object] }
      Configuration = T.type_alias { T::Hash[String, Object] }
      Job = T.type_alias { T::Hash[Symbol, Object] }
      # Reconciliation is invoked from a persisted inbox record (integer) or a
      # transport adapter (string); Controller::Source revalidates either form.
      InboxId = T.type_alias { T.any(Integer, String) }

      sig do
        params(
          db: Sequel::Database,
          herdr: Domains::Sessions::Herdr,
          source: Domains::Controller::Source,
          callback_url: String,
          credential_root: String,
          policy: Domains::Workflows::Policy
        ).void
      end
      def initialize(db, herdr:, source:, callback_url:, credential_root: "/run/herdr/session-credentials", policy: Domains::Workflows::Policy.new)
        @db = db
        @herdr = herdr
        @source = source
        @root = credential_root
        @url = callback_url
        @policy = policy
        @lock = T.let(Domains::Workflows::Lock.new(db), Domains::Workflows::Lock)
      end

      # Called only by operator-configured bootstrap; never exposed as an MCP
      # tool to Worker/Reviewer or accepted from a model-supplied role.
      sig { params(configuration: Configuration).returns(String) }
      def bootstrap(configuration:)
        @lock.call("controller") do
          existing = @db[:sessions][role: "controller", active: true]
          if existing
            queue_renewal(existing) if existing[:credential_expires_at] <= Time.now + 300
            return existing[:id]
          end

          pending = @db[:sessions].where(role: "controller").join(:session_operations, session_id: :id).where(Sequel[:session_operations][:kind] => "start", Sequel[:session_operations][:state] => %w[queued sending uncertain]).select(Sequel[:sessions][:id]).first
          return pending[:id] if pending

          validate_configuration!(configuration)
          id, token = SecureRandom.uuid, SecureRandom.hex(32)
          write_credential(id, token)
          @db.transaction do
            generation = (@db[:sessions].where(role: "controller").max(:generation) || 0) + 1
            @db[:sessions].insert(id: id, role: "controller", generation: generation, pane_id: "pending:#{id}", alias: "digitaltwin-#{id}",
                                  configuration: Sequel.pg_jsonb(configuration), credential_digest: Digest::SHA256.hexdigest(token), credential_expires_at: Time.now + 3600, active: false)
            op = SecureRandom.uuid
            @db[:session_operations].insert(id: op, session_id: id, kind: "start")
            Domains::Jobs::Store.new.enqueue(kind: "session.start", payload: { "operation_id" => op }, key: "session:start:#{id}")
          end
          id
        end
      end

      sig { params(workflow_id: String, role: String).returns(String) }
      def reserve(workflow_id:, role:)
        raise ArgumentError, "Workflow role required" unless %w[writer reviewer].include?(role)

        w = @db[:workflows][id: workflow_id] or raise ArgumentError, "Missing workflow"
        @source.human(w[:source_inbox_id], destination: w[:channel_id])
        @lock.call(workflow_id) do
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
          write_credential(id, token)
          @db.transaction do
            generation = (@db[:sessions].where(workflow_id: workflow_id, role: role).max(:generation) || 0) + 1
            @db[:sessions].insert(id: id, workflow_id: workflow_id, role: role, generation: generation, pane_id: "pending:#{id}", alias: "digitaltwin-#{id}",
                                  configuration: Sequel.pg_jsonb(configuration), credential_digest: Digest::SHA256.hexdigest(token), credential_expires_at: Time.now + 3600, active: false)
            op = SecureRandom.uuid
            @db[:session_operations].insert(id: op, session_id: id, kind: "start")
            Domains::Jobs::Store.new.enqueue(kind: "session.start", payload: { "operation_id" => op }, key: "session:start:#{id}")
            Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: w[:channel_id], thread_id: w[:thread_id], bot: "worker", role: role,
                                                         body: "#{role.capitalize} session #{id} reserved; start operation #{op} is queued, not started.", key: "session:reserved:#{id}")
          end
          id
        end
      end

      sig { params(operation_id: String, before_effect: T.proc.returns(T::Boolean)).returns(String) }
      def execute(operation_id, before_effect: -> { true })
        op = @db[:session_operations][id: operation_id] or raise ArgumentError, "Missing session operation"
        session = @db[:sessions][id: op[:session_id]]
        @lock.call(session[:workflow_id] || "controller") do
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
              env = { "DIGITALTWIN_SESSION_TOKEN_FILE" => credential_path(session[:id]), "DIGITALTWIN_SESSION_GENERATION" => session[:generation].to_s, "DIGITALTWIN_CALLBACK_URL" => @url,
                      "DIGITALTWIN_MASTER_REQUEST_TOKEN_FILE" => File.join(@root, "#{session[:id]}.request-token") }
              created = @herdr.workspace(cwd: w ? w[:worktree_path] : nil, label: session[:alias], env: env)
              pane = object_string(object(created.fetch("root_pane")), "pane_id")
              workspace_id = object_string(object(created.fetch("workspace")), "workspace_id")
              @db[:sessions].where(id: session[:id]).update(pane_id: pane, workspace_id: workspace_id)
              live = @herdr.start(pane, session[:alias], session[:configuration])
              identity = live["agent_session"]
              raise IOError, "Unproved conversation identity" unless identity.is_a?(Hash) && %w[source agent kind value].all? { |key| identity[key].is_a?(String) && !identity[key].empty? }

              @db.transaction do
                @db[:sessions].where(id: session[:id]).update(active: true, runtime_identity: Sequel.pg_jsonb(identity), state: live.fetch("agent_status"), last_verified_at: Time.now)
                complete_operation(op, session, w)
              end
            else
              live = @herdr.get(session[:pane_id])
              raise IOError, "Uncertain or replaced session" unless live["agent_session"] == session[:runtime_identity] && %w[idle done].include?(live["agent_status"])

              @herdr.close(session[:pane_id])
              @db.transaction do
                @db[:sessions].where(id: session[:id]).update(active: false, state: "done")
                complete_operation(op, session, w)
              end
              FileUtils.rm_f(credential_path(session[:id]))
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
          Domains::Jobs::Store.new.enqueue(kind: "workflow.phase_prompt", payload: { "workflow_id" => workflow_id, "version" => version }, key: "workflow:phase:#{workflow_id}:#{version}")
        elsif workflow && row_string(op, :kind) == "stop" && %w[closed cancelled].include?(row_string(workflow, :phase)) && @db[:sessions].where(workflow_id: row_string(workflow, :id), active: true).empty?
          @db[:workflows].where(id: row_string(workflow, :id)).update(archived_at: Time.now)
        end
      end

      sig { params(session: Row).returns(String) }
      def queue_renewal(session) = self.class.schedule_renewal(@db, session)

      class << self
        extend T::Sig

        sig { params(db: Sequel::Database, session: Row).returns(String) }
        def schedule_renewal(db, session)
          id = row_string(session, :id)
          expires_at = row_time(session, :credential_expires_at)
          key = "session:renew:#{id}:#{expires_at.to_i}"
          Domains::Jobs::Store.new.enqueue(kind: "session.renew", payload: { "session_id" => id, "generation" => row_integer(session, :generation) }, key: key, available_at: [Time.now, expires_at - 300].max)
        end
      end

      public

      sig { params(job: Job, store: Domains::Jobs::Store).void }
      def renew_job(job, store)
        id = row_string(job, :id)
        lease_token = row_string(job, :lease_token)
        unless @policy.dispatch_allowed?
          store.block(id: id, lease_token: lease_token, reason: "Live session renewal evidence required")
          return
        end
        payload = row_object(job, :payload)
        renew(session_id: object_string(payload, "session_id"), generation: object_integer(payload, "generation"))
      end

      sig { params(session_id: String, generation: Integer).void }
      def renew(session_id:, generation:)
        s = @db[:sessions][id: session_id, generation: generation, active: true] or raise ArgumentError, "Inactive renewal session"
        @lock.call(s[:workflow_id] || "controller") do
          s = @db[:sessions][id: session_id, generation: generation, active: true] or raise ArgumentError, "Inactive renewal session"
          scope = s[:workflow_id] ? { workflow_id: s[:workflow_id], role: s[:role] } : { role: "controller" }
          raise ArgumentError, "Session replaced" unless @db[:sessions].where(scope).max(:generation) == generation

          w = s[:workflow_id] && @db[:workflows][id: s[:workflow_id]]
          @source.human(w[:source_inbox_id], destination: w[:channel_id]) if w
          live = @herdr.get(s[:pane_id])
          raise ArgumentError, "Session identity not proven" unless s[:runtime_identity] && live["agent_session"] == s[:runtime_identity] && %w[idle working done].include?(live["agent_status"])

          token = File.read(credential_path(s[:id]))
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

      sig { params(operation_id: String, inbox_id: InboxId, pane_id: String).returns(String) }
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

        @lock.call(w ? w[:id] : "controller") do
          op = @db[:session_operations][id: operation_id]
          key = "session:recovery:#{operation_id}"
          receipt = @db[:audit][event_key: key]
          if receipt
            raise ArgumentError, "Recovery pane changed" unless receipt[:details]["pane_id"] == pane_id

            return "complete"
          end
          raise ArgumentError, "Operation not uncertain" unless %w[sending uncertain].include?(op[:state])

          s = @db[:sessions][id: s[:id]]
          raise ArgumentError, "Session generation replaced" unless @db[:sessions].where(w ? { workflow_id: w[:id], role: s[:role] } : { role: "controller" }).max(:generation) == s[:generation]
          raise ArgumentError, "Different recorded pane" unless s[:pane_id].start_with?("pending:") || s[:pane_id] == pane_id

          job = @db[:jobs][dispatch_key: "session:#{op[:kind]}:#{s[:id]}"]
          raise ArgumentError, "Operation lease still live" if job && job[:status] == "running" && job[:lease_expires_at] && job[:lease_expires_at] > Time.now

          changes = if op[:kind] == "start"
                      raise ArgumentError, "Workflow closed" if w && (w[:archived_at] || %w[closed cancelled].include?(w[:phase]))

                      live = @herdr.get(pane_id)
                      identity = live["agent_session"]
                      valid = identity.is_a?(Hash) && %w[source agent kind value].all? { |field| identity[field].is_a?(String) && !identity[field].empty? }
                      valid &&= live["name"] == s[:alias] && live["cwd"] == (w ? w[:worktree_path] : "/home/runtime") && live["agent"] == s[:configuration]["cli"] && identity["agent"] == s[:configuration]["cli"]
                      valid &&= %w[idle done].include?(live["agent_status"]) && live["interactive_ready"] == true && live["launch_pending"] == false
                      raise ArgumentError, "Unproved exact role conversation" unless valid

                      token = File.read(credential_path(s[:id]))
                      raise ArgumentError, "Credential changed" unless Digest::SHA256.hexdigest(token) == s[:credential_digest]

                      { pane_id: pane_id, active: true, runtime_identity: Sequel.pg_jsonb(identity), state: live["agent_status"], credential_expires_at: Time.now + 3600, last_verified_at: Time.now }
                    else
                      raise ArgumentError, "Stop pane mismatch" unless s[:pane_id] == pane_id
                      raise ArgumentError, "Recorded pane still exists" if @herdr.panes.any? { |pane| pane["pane_id"] == pane_id }

                      { active: false, state: "done" }
                    end
          @db.transaction do
            @db[:sessions].where(id: s[:id]).update(changes)
            complete_operation(op, s, w && @db[:workflows][id: w[:id]])
            @db[:jobs].where(id: job[:id]).update(status: "complete", lease_token: nil, lease_expires_at: nil) if job
            @db[:audit].insert(event_key: key, action: "verified_session_reconciliation", details: Sequel.pg_jsonb({ "inbox_id" => inbox_id, "operation_id" => operation_id, "session_id" => s[:id], "generation" => s[:generation], "pane_id" => pane_id }))
            Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: d.channel_id, thread_id: d.thread_id, bot: "agent", role: "controller", body: "Session operation #{operation_id} reconciled against runtime evidence; no start or stop was repeated.", key: key)
          end
          FileUtils.rm_f(credential_path(s[:id])) if op[:kind] == "stop"
          "complete"
        end
      end

      sig { params(workflow_id: String).void }
      def stop(workflow_id:)
        @lock.call(workflow_id) do
          @db.transaction do
            @db[:sessions].where(workflow_id: workflow_id, active: true).each do |s|
              next if @db[:session_operations][session_id: s[:id], kind: "stop"]

              op = SecureRandom.uuid
              @db[:session_operations].insert(id: op, session_id: s[:id], kind: "stop")
              Domains::Jobs::Store.new.enqueue(kind: "session.stop", payload: { "operation_id" => op }, key: "session:stop:#{s[:id]}")
            end
          end
        end
      end

      sig { params(job: Job, store: Domains::Jobs::Store).void }
      def call(job, store)
        id = row_string(job, :id)
        lease_token = row_string(job, :lease_token)
        state = execute(object_string(row_object(job, :payload), "operation_id"), before_effect: -> { store.begin_effect(id: id, lease_token: lease_token) })
        if state == "queued" && @policy.dispatch_allowed?
          store.defer(id: id, lease_token: lease_token, reason: "Session start waits for phase")
        elsif state != "complete"
          store.block(id: id, lease_token: lease_token, reason: "Session #{state}; evidence/reconciliation required")
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
      def credential_path(id) = File.join(@root, "#{id}.token")

      sig { params(id: String, token: String).void }
      def write_credential(id, token)
        FileUtils.mkdir_p(@root, mode: 0700)
        raise ArgumentError, "Credential root symlink" if File.symlink?(@root)

        File.open(credential_path(id), File::WRONLY | File::CREAT | File::EXCL, 0600) { |file| file.write(token) }
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

      sig { params(row: Row, key: Symbol).returns(T::Hash[String, Object]) }
      def row_object(row, key)
        value = row.fetch(key) { raise ArgumentError, "Malformed database row" }
        object(value)
      end

      sig { params(value: Object).returns(T::Hash[String, Object]) }
      def object(value)
        raise ArgumentError, "Malformed JSON object" unless value.is_a?(Hash)

        typed = T.let({}, T::Hash[String, Object])
        value.each do |key, item|
          raise ArgumentError, "Malformed JSON object" unless key.is_a?(String)

          typed[key] = item
        end
        typed
      end

      sig { params(object: T::Hash[String, Object], key: String).returns(String) }
      def object_string(object, key)
        value = object.fetch(key) { raise ArgumentError, "Malformed JSON object" }
        raise ArgumentError, "Malformed JSON object" unless value.is_a?(String)

        value
      end

      sig { params(object: T::Hash[String, Object], key: String).returns(Integer) }
      def object_integer(object, key)
        value = object.fetch(key) { raise ArgumentError, "Malformed JSON object" }
        raise ArgumentError, "Malformed JSON object" unless value.is_a?(Integer)

        value
      end
    end
  end
end
