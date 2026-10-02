# typed: strict
# frozen_string_literal: true

module Domains
  module Controller
    class Services
      extend T::Sig

      HandlerMap = T.type_alias { T::Hash[String, Object] }
      Roles = T.type_alias { Domains::Workflows::Provision::Roles }

      sig { returns(T.nilable(Master)) }
      attr_reader :master

      sig { returns(Routing) }
      attr_reader :routing

      sig { returns(Approvals) }
      attr_reader :approvals

      sig { returns(Domains::Sessions::Lifecycle) }
      attr_reader :sessions

      sig { returns(Domains::Workflows::Provision) }
      attr_reader :provision

      sig { returns(Domains::Reviews::Coordinator) }
      attr_reader :reviews

      sig { returns(Domains::Workflows::Coordinator) }
      attr_reader :workflows

      sig { returns(Source) }
      attr_reader :source

      sig { params(db: Sequel::Database).returns(Services) }
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

      sig do
        params(db: Sequel::Database, resolver: Source::DeliveryResolver,
               membership: T.proc.params(channel_id: String, user_id: String).returns(T::Boolean),
               client: Domains::Mattermost::Client, bot_id: String, roles: Roles,
               policy: Domains::Workflows::Policy, herdr: Domains::Sessions::Herdr,
               evidence: Domains::Reviews::GitEvidence, workspace: T.nilable(Domains::Projects::Workspace),
               credential_root: String).void
      end
      def initialize(db, resolver:, membership:, client:, bot_id:, roles:, policy: Domains::Workflows::Policy.new,
                     herdr: Domains::Sessions::Herdr.new, evidence: Domains::Reviews::GitEvidence.new,
                     workspace: nil, credential_root: "/run/herdr/session-credentials")
        @db = T.let(db, Sequel::Database)
        @source = T.let(Source.new(db, resolver: resolver, membership: membership), Source)
        @approvals = T.let(Approvals.new(db, resolver: resolver, membership: membership, current_commit: Domains::Controller::GitRevision.new, evidence: evidence), Approvals)
        @routing = T.let(Routing.new(db, resolver: resolver, membership: membership, approvals: @approvals), Routing)
        @sessions = T.let(
          Domains::Sessions::Lifecycle.new(db, herdr: herdr, source: @source, credential_root: credential_root,
                                               callback_url: ENV.fetch("DIGITALTWIN_CALLBACK_URL", "http://backend-web:3000"), policy: policy),
          Domains::Sessions::Lifecycle
        )
        @reviews = T.let(Domains::Reviews::Coordinator.new(db, herdr: herdr, evidence: evidence, routing: @routing, policy: policy), Domains::Reviews::Coordinator)
        @workflows = T.let(Domains::Workflows::Coordinator.new(db, source: @source, herdr: herdr, evidence: evidence, reviews: @reviews, sessions: @sessions, policy: policy), Domains::Workflows::Coordinator)
        @provision = T.let(Domains::Workflows::Provision.new(db, source: @source, client: client, bot_id: bot_id,
                                                                 workspace: workspace || Domains::Projects::Workspace.new, sessions: @sessions, roles: roles, policy: policy), Domains::Workflows::Provision)
        controller_role = roles["controller"]
        @master = T.let(controller_role && Master.new(db, sessions: @sessions, source: @source, herdr: herdr,
                                                          configuration: controller_role, credential_root: credential_root, policy: policy), T.nilable(Master))
        @followups = T.let(Followups.new(db, herdr: herdr, resolver: resolver, membership: membership, policy: policy), Followups)
      end

      sig { returns(HandlerMap) }
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

      sig { params(job: Domains::Jobs::Store::Job, _store: Domains::Jobs::Store).void }
      def review_callback(job, _store)
        p = job.payload
        if p["action"] == "artifact"
          @reviews.ready_session(session_id: payload_string(p, "session_id"), generation: payload_integer(p, "generation"), kind: payload_string(p, "kind"), commit: payload_string(p, "commit"))
        else
          @reviews.finish_session(session_id: payload_string(p, "session_id"), generation: payload_integer(p, "generation"), review_commit: payload_string(p, "commit"), verdict: payload_string(p, "verdict"))
        end
      end

      sig { params(job: Domains::Jobs::Store::Job, _store: Domains::Jobs::Store).void }
      def master_control(job, _store)
        payload = job.payload
        @workflows.control(inbox_id: payload_string(payload, "inbox_id"), workflow_id: payload_string(payload, "workflow_id"),
                           action: payload_string(payload, "action"), expected_version: payload_integer(payload, "expected_version"))
      end

      sig { params(job: Domains::Jobs::Store::Job, store: Domains::Jobs::Store).void }
      def route(job, store)
        id = inbox_id(job)
        source = @source.human(id)
        start_recovery = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} recover-start ([0-9a-f-]+) ([a-z0-9]{26})\z/)
        if start_recovery
          @provision.reconcile(id: capture(start_recovery, 1), inbox_id: string_id(id), thread_id: capture(start_recovery, 2))
          return
        end
        session_recovery = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} recover-session ([0-9a-f-]+) ([a-zA-Z0-9_.:-]+)\z/)
        if session_recovery
          @sessions.reconcile(operation_id: capture(session_recovery, 1), inbox_id: string_id(id), pane_id: capture(session_recovery, 2))
          return
        end
        followup_recovery = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} recover-followup ([0-9]+) (delivered|discard)\z/)
        if followup_recovery
          @followups.reconcile(id: capture(followup_recovery, 1).to_i, inbox_id: id, outcome: capture(followup_recovery, 2))
          return
        end
        recovery = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} recover-master ([0-9a-f-]+)\z/)
        if recovery
          raise ArgumentError, "Master not configured" unless @master

          @master.recover(request_id: capture(recovery, 1), inbox_id: id)
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
        @workflows.advance_approval(workflow_id: capture(match, 1), gate: capture(match, 2)) if match
      end

      sig { params(job: Domains::Jobs::Store::Job, _store: Domains::Jobs::Store).void }
      def control_existing(job, _store)
        payload = job.payload
        inbox_id = payload_string(payload, "inbox_id")
        workflow_id = payload_string(payload, "workflow_id")
        d = @source.human(inbox_id)
        w = @db[:workflows][id: workflow_id]
        action = job.kind.delete_prefix("workflow.")
        raise ArgumentError, "Control source/workflow mismatch" unless w && d.channel_id == w[:channel_id] && d.thread_id == w[:thread_id] && d.body == "@#{ENV.fetch("WORKER_HANDLE", "worker")} #{action}"

        @workflows.control(inbox_id: inbox_id, workflow_id: w[:id], action: action, expected_version: payload_integer(payload, "expected_version"))
      end

      sig { params(job: Domains::Jobs::Store::Job, _store: Domains::Jobs::Store).void }
      def approve_existing(job, _store)
        payload = job.payload
        inbox_id = payload_string(payload, "inbox_id")
        d = @source.human(inbox_id)
        w = @db[:workflows][id: payload_string(payload, "workflow_id")]
        raise ArgumentError, "Approval source/workflow mismatch" unless w && d.channel_id == w[:channel_id] && d.thread_id == w[:thread_id] && w[:version] == payload_integer(payload, "expected_version")

        gate = w[:phase].delete_suffix("_human_approval")
        ref = w[:artifacts].fetch(gate)
        @approvals.record(inbox_id: inbox_id, workflow_id: w[:id], gate: gate, commit: ref.fetch("commit"))
        @workflows.advance_approval(workflow_id: w[:id], gate: gate)
      end

      sig { params(job: Domains::Jobs::Store::Job, _store: Domains::Jobs::Store).void }
      def start_existing(job, _store)
        id = inbox_id(job)
        d = @source.human(id)
        raise ArgumentError, "Human root start required" unless d.root_post && d.body.match?(/\A@#{Regexp.escape(ENV.fetch("WORKER_HANDLE", "worker"))} start\b/)

        project = @db[:projects][channel_id: d.channel_id]
        raise ArgumentError, "Use verified project mapping through Master" unless project

        @provision.request(inbox_id: string_id(id), project_id: project[:id], title: d.body, existing_thread: d.thread_id)
      end

      private

      sig { params(job: Domains::Jobs::Store::Job).returns(T.any(Integer, String)) }
      def inbox_id(job)
        value = job.payload.fetch("inbox_id") { raise ArgumentError, "Controller job is malformed" }
        raise ArgumentError, "Controller job is malformed" unless value.is_a?(Integer) || value.is_a?(String)

        value
      end

      sig { params(value: T.any(Integer, String)).returns(String) }
      def string_id(value)
        return value if value.is_a?(String)

        value.to_s
      end

      sig { params(match: T.nilable(MatchData), index: Integer).returns(String) }
      def capture(match, index)
        value = match&.[](index)
        raise ArgumentError, "Invalid controller command" unless value.is_a?(String)

        value
      end

      sig { params(payload: Domains::Jobs::Store::Payload, key: String).returns(String) }
      def payload_string(payload, key)
        value = payload.fetch(key) { raise ArgumentError, "Controller job is malformed" }
        raise ArgumentError, "Controller job is malformed" unless value.is_a?(String)

        value
      end

      sig { params(payload: Domains::Jobs::Store::Payload, key: String).returns(Integer) }
      def payload_integer(payload, key)
        value = payload.fetch(key) { raise ArgumentError, "Controller job is malformed" }
        raise ArgumentError, "Controller job is malformed" unless value.is_a?(Integer)

        value
      end
    end
  end
end
