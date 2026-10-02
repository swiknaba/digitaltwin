# frozen_string_literal: true

module Domains
  module Controller
    class Services
      attr_reader :master, :routing, :approvals, :sessions, :provision, :reviews, :workflows, :source

      def self.from_env(db)
        client = Domains::Mattermost::Client.new(url: ENV.fetch("MATTERMOST_URL"), token_file: ENV.fetch("MATTERMOST_LISTENER_TOKEN_FILE"))
        resolver = Domains::Mattermost::ActorResolver.new(client, local_bot_ids: ENV.fetch("MATTERMOST_LOCAL_BOT_IDS").split(","), peer_bot_ids: ENV.fetch("MATTERMOST_PEER_BOT_IDS", "").split(","))
        membership = ->(channel, user) do
          member = client.get("/api/v4/channels/#{channel}/members/#{user}")
          member["channel_id"] == channel && member["user_id"] == user
        rescue Domains::Mattermost::Client::Error
          false
        end
        roles = ENV["ROLE_CONFIG_FILE"] ? JSON.parse(File.read(ENV.fetch("ROLE_CONFIG_FILE"))) : {}
        worker = Domains::Mattermost::Client.new(url: ENV.fetch("MATTERMOST_URL"), token_file: ENV.fetch("MATTERMOST_WORKER_TOKEN_FILE"))
        new(db, resolver: resolver, membership: membership, client: worker, bot_id: ENV.fetch("MATTERMOST_WORKER_BOT_ID"), roles: roles)
      end

      def initialize(db, resolver:, membership:, client:, bot_id:, roles:, policy: Domains::Workflows::Policy.new,
                     herdr: Domains::Sessions::Herdr.new, evidence: Domains::Reviews::GitEvidence.new,
                     workspace: nil, credential_root: "/run/herdr/session-credentials")
        @db = db
        @source = Source.new(db, resolver: resolver, membership: membership)
        @approvals = Approvals.new(db, resolver: resolver, membership: membership, current_commit: Domains::Controller::GitRevision.new, evidence: evidence)
        @routing = Routing.new(db, resolver: resolver, membership: membership, approvals: @approvals)
        @sessions = Domains::Sessions::Lifecycle.new(db, herdr: herdr, source: @source, credential_root: credential_root,
                                                         callback_url: ENV.fetch("DIGITALTWIN_CALLBACK_URL", "http://backend:3000"), policy: policy)
        @reviews = Domains::Reviews::Coordinator.new(db, herdr: herdr, evidence: evidence, routing: @routing, policy: policy)
        @workflows = Domains::Workflows::Coordinator.new(db, source: @source, herdr: herdr, evidence: evidence, reviews: @reviews, sessions: @sessions, policy: policy)
        @provision = Domains::Workflows::Provision.new(db, source: @source, client: client, bot_id: bot_id,
                                                           workspace: workspace || LazyWorkspace.new, sessions: @sessions, roles: roles, policy: policy)
        @master = roles["controller"] && Master.new(db, sessions: @sessions, source: @source, herdr: herdr,
                                                        configuration: roles["controller"], credential_root: credential_root, policy: policy)
        @followups = Followups.new(db, herdr: herdr, resolver: resolver, membership: membership, policy: policy)
      end

      def handlers
        values = { "master.prompt" => method(:route), "workflow.prompt" => @routing.method(:call),
                   "session.followup" => @followups.method(:call), "workflow.provision" => @provision.method(:call),
                   "session.start" => @sessions.method(:call), "session.stop" => @sessions.method(:call),
                   "review.prompt" => @reviews.method(:call), "review.release" => @reviews.method(:release_job),
                   "review.callback" => method(:review_callback), "master.control" => method(:master_control), "session.renew" => @sessions.method(:renew_job), "workflow.phase_prompt" => @workflows.method(:call),
                   "workflow.start" => method(:start_existing) }
        %w[pause resume finish cancel].each { |action| values["workflow.#{action}"] = method(:control_existing) }
        values["workflow.approve"] = method(:approve_existing)
        values["master.dispatch"] = @master.method(:call) if @master
        values
      end

      def review_callback(job, _store)
        p = job[:payload]
        if p["action"] == "artifact"
          @reviews.ready_session(session_id: p.fetch("session_id"), generation: p.fetch("generation"), kind: p.fetch("kind"), commit: p.fetch("commit"))
        else
          @reviews.finish_session(session_id: p.fetch("session_id"), generation: p.fetch("generation"), review_commit: p.fetch("commit"), verdict: p.fetch("verdict"))
        end
      end

      def master_control(job, _store)
        @workflows.control(**job[:payload].transform_keys(&:to_sym))
      end

      def route(job, store)
        id = job[:payload].fetch("inbox_id")
        source = @source.human(id)
        recovery = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} recover-master ([0-9a-f-]+)\z/)
        if recovery
          raise ArgumentError, "Master not configured" unless @master

          @master.recover(request_id: recovery[1], inbox_id: id)
          return
        end
        if @master && !source.body.match?(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} (approve|route)\b/)
          @master.ingest(id)
          return
        end
        @routing.call(job, store)
        # Exact approvals advance only through the coordinator's independent
        # revision/gate validation. Normal contextual prompts keep their session.
        source = @source.human(id)
        match = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} approve ([a-zA-Z0-9-]+) (spec|plan) ([0-9a-f]{40})\z/)
        @workflows.advance_approval(workflow_id: match[1], gate: match[2]) if match
      end

      def control_existing(job, _store)
        payload = job[:payload]
        d = @source.human(payload.fetch("inbox_id"))
        w = @db[:workflows][id: payload.fetch("workflow_id")]
        action = job[:kind].delete_prefix("workflow.")
        raise ArgumentError, "Control source/workflow mismatch" unless w && d.channel_id == w[:channel_id] && d.thread_id == w[:thread_id] && d.body == "@#{ENV.fetch('WORKER_HANDLE', 'worker')} #{action}"

        @workflows.control(inbox_id: payload["inbox_id"], workflow_id: w[:id], action: action, expected_version: payload.fetch("expected_version"))
      end

      def approve_existing(job, _store)
        payload = job[:payload]
        d = @source.human(payload.fetch("inbox_id"))
        w = @db[:workflows][id: payload.fetch("workflow_id")]
        raise ArgumentError, "Approval source/workflow mismatch" unless w && d.channel_id == w[:channel_id] && d.thread_id == w[:thread_id] && w[:version] == payload.fetch("expected_version")

        gate = w[:phase].delete_suffix("_human_approval")
        ref = w[:artifacts].fetch(gate)
        @approvals.record(inbox_id: payload["inbox_id"], workflow_id: w[:id], gate: gate, commit: ref.fetch("commit"))
        @workflows.advance_approval(workflow_id: w[:id], gate: gate)
      end

      def start_existing(job, _store)
        id = job[:payload].fetch("inbox_id")
        d = @source.human(id)
        raise ArgumentError, "Human root start required" unless d.root_post && d.body.match?(/\A@#{Regexp.escape(ENV.fetch("WORKER_HANDLE", "worker"))} start\b/)

        project = @db[:projects][channel_id: d.channel_id]
        raise ArgumentError, "Use verified project mapping through Master" unless project

        @provision.request(inbox_id: id, project_id: project[:id], title: d.body, existing_thread: d.thread_id)
      end

      class LazyWorkspace
        def for_workflow(**args) = Domains::Projects::Workspace.new.for_workflow(**args)
      end
    end
  end
end
