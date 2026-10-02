# typed: strict
# frozen_string_literal: true

require "digest"
module Domains
  module Workflows
    class Provision
      extend T::Sig

      Role = T.type_alias { T::Hash[String, String] }
      Roles = T.type_alias { T::Hash[String, Role] }
      Job = T.type_alias { T::Hash[Symbol, Object] }
      # Inbox rows are PostgreSQL integer primary keys. String IDs are retained
      # for callers that originate from a transport adapter and are validated by
      # Controller::Source before becoming authority for a workflow action.
      InboxId = T.type_alias { T.any(Integer, String) }

      sig do
        params(
          db: Sequel::Database,
          source: Domains::Controller::Source,
          client: Domains::Mattermost::Client,
          bot_id: String,
          workspace: Domains::Projects::Workspace,
          sessions: Domains::Sessions::Lifecycle,
          roles: Roles,
          policy: Policy
        ).void
      end
      def initialize(db, source:, client:, bot_id:, workspace:, sessions:, roles:, policy: Policy.new)
        @db = db
        @source = source
        @client = client
        @bot = bot_id
        @workspace = workspace
        @sessions = sessions
        @roles = roles
        @policy = policy
      end

      sig { params(inbox_id: InboxId, project_id: String, title: String, existing_thread: T.nilable(String)).returns(String) }
      def request(inbox_id:, project_id:, title:, existing_thread: nil)
        project = @db[:projects][id: project_id] or raise ArgumentError, "Unknown project"
        d = @source.human(inbox_id, destination: project[:channel_id])
        raise ArgumentError, "Invalid title" unless title.bytesize.between?(1, 1000)
        raise ArgumentError, "Existing thread must be verified human source" if existing_thread && (d.channel_id != project[:channel_id] || d.thread_id != existing_thread || !d.root_post)

        writer, reviewer = @roles.fetch("writer"), @roles.fetch("reviewer")
        raise ArgumentError, "Writer/reviewer diversity required" unless writer.fetch("provider") != reviewer.fetch("provider") && writer.fetch("family") != reviewer.fetch("family")

        parameters = { "title" => title, "existing_thread" => existing_thread, "roles" => @roles }
        digest = Digest::SHA256.hexdigest(JSON.generate([project_id, parameters]))
        @db.transaction do
          @db[:inbox].where(id: inbox_id).for_update.first
          old = @db[:workflow_requests][inbox_id: inbox_id]
          if old
            raise ArgumentError, "Start source already bound" unless old[:request_digest] == digest

            return old[:id]
          end
          id = SecureRandom.uuid
          @db[:workflow_requests].insert(id: id, inbox_id: inbox_id, project_id: project_id, request_digest: digest, parameters: Sequel.pg_jsonb(parameters), thread_id: existing_thread)
          Domains::Jobs::Store.new(@db).enqueue(kind: "workflow.provision", payload: { "request_id" => id }, key: "workflow:provision:#{id}")
          Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: d.channel_id, thread_id: d.thread_id, bot: "agent", role: "controller", body: "Workflow request #{id} queued; project thread and sessions are not yet created.", key: "workflow:request:#{id}")
          id
        end
      end

      sig { params(id: String, before_effect: T.proc.returns(T::Boolean)).returns(String) }
      def execute(id, before_effect: -> { true })
        Domains::Workflows::Lock.new(@db).call("provision:#{id}") do
          request = @db[:workflow_requests][id: id] or raise ArgumentError, "Missing workflow request"
          return request[:state] unless request[:state] == "queued"
          return "queued" unless @policy.dispatch_allowed?

          project = @db[:projects][id: request[:project_id]]
          delivery = @source.human(request[:inbox_id], destination: project[:channel_id])
          thread = request[:thread_id]
          unless thread
            me = @client.get("/api/v4/users/me")
            member = @client.get("/api/v4/channels/#{project[:channel_id]}/members/#{@bot}")
            raise ArgumentError, "Unverified thread bot" unless me["id"] == @bot && me["is_bot"] == true && member["channel_id"] == project[:channel_id] && member["user_id"] == @bot

            @db[:workflow_requests].where(id: id).update(state: "sending")
            begin
              raise IOError, "Dispatch lease lost" unless before_effect.call

              payload = { "channel_id" => project[:channel_id], "root_id" => "", "message" => request[:parameters].fetch("title"), "props" => { "digitaltwin_workflow_request" => id } }
              post = @client.post("/api/v4/posts", payload)
              post_id = client_identifier(post, "id")
              valid = post_id.match?(/\A[a-z0-9]{26}\z/) && post["channel_id"] == project[:channel_id]
              valid &&= post["root_id"].to_s.empty? && post["user_id"] == @bot && post["message"] == request[:parameters]["title"]
              valid &&= client_properties(post)["digitaltwin_workflow_request"] == id
              raise IOError, "Unverified created thread" unless valid

              thread = post_id
              @db[:workflow_requests].where(id: id).update(thread_id: thread, state: "queued")
            rescue StandardError
              @db[:workflow_requests].where(id: id).update(state: "uncertain", reason: "Thread creation requires reconciliation; do not repeat")
              return "uncertain"
            end
          end
          workflow = bind(request, project, thread, delivery)
          workflow_id = row_string(workflow, :id)
          path = @workspace.for_workflow(slug: project[:slug], workflow_id: workflow_id, branch: row_string(workflow, :branch))
          raise ArgumentError, "Worktree binding changed" unless path == row_string(workflow, :worktree_path)

          @sessions.reserve(workflow_id: workflow_id, role: "writer")
          @sessions.reserve(workflow_id: workflow_id, role: "reviewer")
          @db[:workflow_requests].where(id: id).update(state: "bound")
          "bound"
        end
      end

      sig { params(job: Job, store: Domains::Jobs::Store).void }
      def call(job, store)
        request_id = payload_string(job, "request_id")
        job_id = job_string(job, :id)
        lease_token = job_string(job, :lease_token)
        state = execute(request_id, before_effect: -> { store.begin_effect(id: job_id, lease_token: lease_token) })
        store.block(id: job_id, lease_token: lease_token, reason: "Provision #{state}; evidence/reconciliation required") unless state == "bound"
      end

      sig { params(id: String, inbox_id: InboxId, thread_id: String).returns(String) }
      def reconcile(id:, inbox_id:, thread_id:)
        raise ArgumentError, "Invalid thread" unless thread_id.match?(/\A[a-z0-9]{26}\z/)

        Domains::Workflows::Lock.new(@db).call("provision:#{id}") do
          request = @db[:workflow_requests][id: id] or raise ArgumentError, "Unknown start request"
          project = @db[:projects][id: request[:project_id]]
          d = @source.human(inbox_id, destination: project[:channel_id])
          original = @db[:inbox][id: request[:inbox_id]]
          command = "@#{ENV.fetch("AGENT_HANDLE", "agent")} recover-start #{id} #{thread_id}"
          raise ArgumentError, "Exact original-human thread recovery required" unless d.actor.user_id == original[:user_id] && d.body == command

          key = "workflow:recovery:#{id}"
          receipt = @db[:audit][event_key: key]
          if receipt
            raise ArgumentError, "Recovery thread changed" unless receipt[:details]["thread_id"] == thread_id

            return "queued"
          end
          raise ArgumentError, "Start does not require reconciliation" unless %w[sending uncertain].include?(request[:state])

          job = @db[:jobs][dispatch_key: "workflow:provision:#{id}"]
          raise ArgumentError, "Creation lease still live" if job && job[:status] == "running" && job[:lease_expires_at] && job[:lease_expires_at] > Time.now

          me = @client.get("/api/v4/users/me")
          member = @client.get("/api/v4/channels/#{project[:channel_id]}/members/#{@bot}")
          post = @client.get("/api/v4/posts/#{thread_id}")
          valid = me["id"] == @bot && me["is_bot"] == true && member["channel_id"] == project[:channel_id] && member["user_id"] == @bot
          valid &&= post["id"] == thread_id && post["channel_id"] == project[:channel_id] && post["root_id"].to_s.empty? && post["delete_at"] == 0
          valid &&= post["user_id"] == @bot && post["message"] == request[:parameters]["title"] && client_properties(post)["digitaltwin_workflow_request"] == id
          raise ArgumentError, "Unproved created thread" unless valid

          @db.transaction do
            @db[:workflow_requests].where(id: id).update(thread_id: thread_id, state: "queued", reason: nil)
            @db[:jobs].where(id: job[:id]).update(status: "complete", lease_token: nil, lease_expires_at: nil) if job
            Domains::Jobs::Store.new(@db).enqueue(kind: "workflow.provision", payload: { "request_id" => id }, key: "workflow:provision:reconciled:#{id}:#{thread_id}")
            @db[:audit].insert(event_key: key, action: "verified_thread_reconciliation", details: Sequel.pg_jsonb({ "inbox_id" => inbox_id, "request_id" => id, "thread_id" => thread_id }))
            Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: d.channel_id, thread_id: d.thread_id, bot: "agent", role: "controller", body: "Start #{id} reconciled to verified thread #{thread_id}; continuation queued without recreating the thread.", key: key)
          end
          "queued"
        end
      end

      private

      sig do
        params(
          request: T::Hash[Symbol, Object],
          project: T::Hash[Symbol, Object],
          thread: String,
          delivery: Domains::Mattermost::VerifiedDelivery
        ).returns(T::Hash[Symbol, Object])
      end
      def bind(request, project, thread, delivery)
        @db.transaction do
          @db[:workflow_requests].where(id: request[:id]).for_update.first
          if request[:workflow_id]
            return @db[:workflows][id: request[:workflow_id]]
          end
          raise ArgumentError, "Active thread already owns a workflow" if @db[:workflows][channel_id: project[:channel_id], thread_id: thread, archived_at: nil]

          id = SecureRandom.uuid
          root = ENV.fetch("WORKTREE_ROOT", "/workspace/worktrees")
          @db[:workflows].insert(id: id, project_id: project[:id], channel_id: project[:channel_id], thread_id: thread,
                                 branch: "digitaltwin/#{id}", worktree_path: File.join(root, id), source_inbox_id: request[:inbox_id], role_configurations: Sequel.pg_jsonb(object_value(request, :parameters).fetch("roles")))
          @db[:workflow_requests].where(id: request[:id]).update(workflow_id: id)
          threads = [delivery.thread_id]
          threads << "master" if delivery.root_post && delivery.channel_id == ENV["MASTER_CHANNEL_ID"]
          threads.each do |context_thread|
            values = { workflow_id: id, inbox_id: request[:inbox_id], updated_at: Time.now }
            @db[:conversation_bindings].insert_conflict(target: %i[channel_id thread_id user_id], update: values).insert(**values, channel_id: delivery.channel_id, thread_id: context_thread, user_id: delivery.actor.user_id)
          end
          @db[:workflows][id: id]
        end
      end

      sig { params(job: Job).returns(T::Hash[String, Object]) }
      def payload(job)
        value = job.fetch(:payload)
        raise ArgumentError, "Invalid provision job" unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }

        value
      end

      sig { params(job: Job, key: String).returns(String) }
      def payload_string(job, key)
        value = payload(job).fetch(key)
        raise ArgumentError, "Invalid provision job" unless value.is_a?(String)

        value
      end

      sig { params(job: Job, key: Symbol).returns(String) }
      def job_string(job, key)
        value = job.fetch(key)
        raise ArgumentError, "Invalid provision job" unless value.is_a?(String)

        value
      end

      sig { params(response: Domains::Mattermost::Client::JsonObject, key: String).returns(String) }
      def client_identifier(response, key)
        value = response.fetch(key)
        raise ArgumentError, "Malformed Mattermost response" unless value.is_a?(String)

        value
      end

      sig { params(response: Domains::Mattermost::Client::JsonObject).returns(T::Hash[String, Object]) }
      def client_properties(response)
        value = response.fetch("props", {})
        raise ArgumentError, "Malformed Mattermost response" unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }

        value
      end

      sig { params(row: T::Hash[Symbol, Object], key: Symbol).returns(String) }
      def row_string(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Malformed database row" unless value.is_a?(String)

        value
      end

      sig { params(row: T::Hash[Symbol, Object], key: Symbol).returns(T::Hash[String, Object]) }
      def object_value(row, key)
        value = row.fetch(key)
        raise ArgumentError, "Malformed database row" unless value.is_a?(Hash) || value.is_a?(Sequel::Postgres::JSONBHash)

        object = value.is_a?(Sequel::Postgres::JSONBHash) ? value.to_hash : value
        raise ArgumentError, "Malformed database row" unless object.keys.all? { |entry| entry.is_a?(String) }

        object
      end
    end
  end
end
