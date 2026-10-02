# frozen_string_literal: true

require "digest"
module Domains
  module Workflows
    class Provision
      def initialize(db, source:, client:, bot_id:, workspace:, sessions:, roles:, policy: Policy.new)
        @db, @source, @client, @bot, @workspace, @sessions, @roles, @policy = db, source, client, bot_id, workspace, sessions, roles, policy
      end

      def request(inbox_id:, project_id:, title:, existing_thread: nil)
        project = @db[:projects][id: project_id] or raise ArgumentError, "Unknown project"
        d = @source.human(inbox_id, destination: project[:channel_id])
        raise ArgumentError, "Invalid title" unless title.is_a?(String) && title.bytesize.between?(1, 1000)
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
          Domains::Mattermost::Outbox.new(@db).enqueue(channel_id: d.channel_id, thread_id: d.thread_id, bot: "agent", role: "controller", body: "Workflow request queued; project thread and sessions are not yet created.", key: "workflow:request:#{id}")
          id
        end
      end

      def execute(id, before_effect: -> { true })
        Domains::Workflows::Lock.new(@db).call("provision:#{id}") do
          request = @db[:workflow_requests][id: id] or raise ArgumentError, "Missing workflow request"
          return request[:state] unless request[:state] == "queued"
          return "queued" unless @policy.dispatch_allowed?

          project = @db[:projects][id: request[:project_id]]
          @source.human(request[:inbox_id], destination: project[:channel_id])
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
              valid = post["id"].is_a?(String) && post["id"].match?(/\A[a-z0-9]{26}\z/) && post["channel_id"] == project[:channel_id]
              valid &&= post["root_id"].to_s.empty? && post["user_id"] == @bot && post["message"] == request[:parameters]["title"]
              valid &&= post.fetch("props", {})["digitaltwin_workflow_request"] == id
              raise IOError, "Unverified created thread" unless valid

              thread = post["id"]
              @db[:workflow_requests].where(id: id).update(thread_id: thread, state: "queued")
            rescue StandardError
              @db[:workflow_requests].where(id: id).update(state: "uncertain", reason: "Thread creation requires reconciliation; do not repeat")
              return "uncertain"
            end
          end
          workflow = bind(request, project, thread)
          path = @workspace.for_workflow(slug: project[:slug], workflow_id: workflow[:id], branch: workflow[:branch])
          raise ArgumentError, "Worktree binding changed" unless path == workflow[:worktree_path]

          @sessions.reserve(workflow_id: workflow[:id], role: "writer")
          @sessions.reserve(workflow_id: workflow[:id], role: "reviewer")
          @db[:workflow_requests].where(id: id).update(state: "bound")
          "bound"
        end
      end

      def call(job, store)
        state = execute(job[:payload].fetch("request_id"), before_effect: -> { store.begin_effect(id: job[:id], lease_token: job[:lease_token]) })
        store.block(id: job[:id], lease_token: job[:lease_token], reason: "Provision #{state}; evidence/reconciliation required") unless state == "bound"
      end

      private def bind(request, project, thread)
        @db.transaction do
          @db[:workflow_requests].where(id: request[:id]).for_update.first
          if request[:workflow_id]
            return @db[:workflows][id: request[:workflow_id]]
          end
          raise ArgumentError, "Active thread already owns a workflow" if @db[:workflows][channel_id: project[:channel_id], thread_id: thread, archived_at: nil]

          id = SecureRandom.uuid
          root = ENV.fetch("WORKTREE_ROOT", "/workspace/worktrees")
          @db[:workflows].insert(id: id, project_id: project[:id], channel_id: project[:channel_id], thread_id: thread,
                                 branch: "digitaltwin/#{id}", worktree_path: File.join(root, id), source_inbox_id: request[:inbox_id], role_configurations: Sequel.pg_jsonb(request[:parameters].fetch("roles")))
          @db[:workflow_requests].where(id: request[:id]).update(workflow_id: id)
          @db[:workflows][id: id]
        end
      end
    end
  end
end
