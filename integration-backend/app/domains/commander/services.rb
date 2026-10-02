# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    class Services
      extend T::Sig

      Kind = Platform::Jobs::Dto::JobKind
      Decision = Platform::Jobs::Dto::Decision
      ClaimedJob = Platform::Jobs::Dto::ClaimedJob
      HandlerMap = T.type_alias { T::Hash[Platform::Jobs::Dto::JobKind, Platform::Jobs::Handler] }
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
        @db = db
        @source = T.let(Source.new(db, resolver: resolver, membership: membership), Source)
        @approvals = T.let(Approvals.new(db, resolver: resolver, membership: membership, current_commit: Domains::Commander::GitRevision.new, evidence: evidence), Approvals)
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
        values = T.let({
                         Kind::MasterPrompt => ->(job) { route(job: job) },
                         Kind::WorkflowPrompt => ->(job) { @routing.call(job: job) },
                         Kind::SessionFollowup => ->(job) { @followups.call(job: job) },
                         Kind::WorkflowProvision => ->(job) { @provision.call(job: job) },
                         Kind::SessionStart => ->(job) { @sessions.call(job: job) },
                         Kind::SessionStop => ->(job) { @sessions.call(job: job) },
                         Kind::ReviewPrompt => ->(job) { @reviews.call(job: job) },
                         Kind::ReviewRelease => ->(job) { @reviews.release_job(job: job) },
                         Kind::ReviewCallback => ->(job) { review_callback(job: job) },
                         Kind::MasterControl => ->(job) { master_control(job: job) },
                         Kind::SessionRenew => ->(job) { @sessions.renew_job(job: job) },
                         Kind::WorkflowPhasePrompt => ->(job) { @workflows.call(job: job) },
                         Kind::WorkflowStart => ->(job) { start_existing(job: job) },
                         Kind::WorkflowPause => ->(job) { control_existing(job: job) },
                         Kind::WorkflowResume => ->(job) { control_existing(job: job) },
                         Kind::WorkflowFinish => ->(job) { control_existing(job: job) },
                         Kind::WorkflowCancel => ->(job) { control_existing(job: job) },
                         Kind::WorkflowApprove => ->(job) { approve_existing(job: job) }
                       }, T::Hash[Platform::Jobs::Dto::JobKind, Platform::Jobs::CallableHandler::Callable])
        master = @master
        values[Kind::MasterDispatch] = ->(job) { master.call(job: job) } if master
        values.transform_values { |callable| Platform::Jobs::CallableHandler.new(callable) }
      end

      sig { params(job: ClaimedJob).returns(Decision) }
      def review_callback(job:)
        p = Domains::Reviews::Dto::CallbackJob.from_hash(job.payload, true)
        if p.action == "artifact"
          @reviews.ready_session(session_id: p.session_id, generation: p.generation, kind: required(p.kind), commit: p.commit)
        else
          @reviews.finish_session(session_id: p.session_id, generation: p.generation, review_commit: p.commit, verdict: required(p.verdict))
        end
        Decision.complete
      end

      sig { params(job: ClaimedJob).returns(Decision) }
      def master_control(job:)
        payload = Dto::MasterControlJob.from_hash(job.payload, true)
        @workflows.control(inbox_id: payload.inbox_id, workflow_id: payload.workflow_id, action: payload.action, expected_version: payload.expected_version)
        Decision.complete
      end

      sig { params(job: ClaimedJob).returns(Decision) }
      def route(job:)
        id = Dto::InboxDispatchJob.from_hash(job.payload, true).inbox_id
        source = @source.human(id)
        start_recovery = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} recover-start ([0-9a-f-]+) ([a-z0-9]{26})\z/)
        if start_recovery
          @provision.reconcile(id: capture(start_recovery, 1), inbox_id: id, thread_id: capture(start_recovery, 2))
          return Decision.complete
        end
        session_recovery = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} recover-session ([0-9a-f-]+) ([a-zA-Z0-9_.:-]+)\z/)
        if session_recovery
          @sessions.reconcile(operation_id: capture(session_recovery, 1), inbox_id: id, pane_id: capture(session_recovery, 2))
          return Decision.complete
        end
        followup_recovery = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} recover-followup ([0-9]+) (delivered|discard)\z/)
        if followup_recovery
          @followups.reconcile(id: capture(followup_recovery, 1).to_i, inbox_id: id, outcome: capture(followup_recovery, 2))
          return Decision.complete
        end
        recovery = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} recover-master ([0-9a-f-]+)\z/)
        if recovery
          raise ArgumentError, "Master not configured" unless @master

          @master.recover(request_id: capture(recovery, 1), inbox_id: id)
          return Decision.complete
        end
        if @master && !source.body.match?(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} (approve|route)\b/)
          @master.ingest(id)
          return Decision.complete
        end
        @routing.call(job: job)
        # Exact approvals advance only through the coordinator's independent
        # revision/gate validation. Normal contextual prompts keep their session.
        source = @source.human(id)
        match = source.body.match(/\A@#{Regexp.escape(ENV.fetch("AGENT_HANDLE", "agent"))} approve ([a-zA-Z0-9-]+) (spec|plan) ([0-9a-f]{40})\z/)
        @workflows.advance_approval(workflow_id: capture(match, 1), gate: capture(match, 2)) if match
        Decision.complete
      end

      sig { params(job: ClaimedJob).returns(Decision) }
      def control_existing(job:)
        payload = Dto::InboxDispatchJob.from_hash(job.payload, true)
        inbox_id = payload.inbox_id
        d = @source.human(inbox_id)
        w = @db[:workflows][id: required(payload.workflow_id)]
        action = job.kind.serialize.delete_prefix("workflow.")
        raise ArgumentError, "Control source/workflow mismatch" unless w && d.channel_id == w[:channel_id] && d.thread_id == w[:thread_id] && d.body == "@#{ENV.fetch("WORKER_HANDLE", "worker")} #{action}"

        @workflows.control(inbox_id: inbox_id, workflow_id: w[:id], action: action, expected_version: required_integer(payload.expected_version))
        Decision.complete
      end

      sig { params(job: ClaimedJob).returns(Decision) }
      def approve_existing(job:)
        payload = Dto::InboxDispatchJob.from_hash(job.payload, true)
        inbox_id = payload.inbox_id
        d = @source.human(inbox_id)
        w = @db[:workflows][id: required(payload.workflow_id)]
        raise ArgumentError, "Approval source/workflow mismatch" unless w && d.channel_id == w[:channel_id] && d.thread_id == w[:thread_id] && w[:version] == required_integer(payload.expected_version)

        gate = w[:phase].delete_suffix("_human_approval")
        ref = w[:artifacts].fetch(gate)
        @approvals.record(inbox_id: inbox_id, workflow_id: w[:id], gate: gate, commit: ref.fetch("commit"))
        @workflows.advance_approval(workflow_id: w[:id], gate: gate)
        Decision.complete
      end

      sig { params(job: ClaimedJob).returns(Decision) }
      def start_existing(job:)
        id = Dto::InboxDispatchJob.from_hash(job.payload, true).inbox_id
        d = @source.human(id)
        raise ArgumentError, "Human root start required" unless d.root_post && d.body.match?(/\A@#{Regexp.escape(ENV.fetch("WORKER_HANDLE", "worker"))} start\b/)

        project = @db[:projects][channel_id: d.channel_id]
        raise ArgumentError, "Use verified project mapping through Master" unless project

        @provision.request(inbox_id: id, project_id: project[:id], title: d.body, existing_thread: d.thread_id)
        Decision.complete
      end

      private

      sig { params(match: T.nilable(MatchData), index: Integer).returns(String) }
      def capture(match, index)
        value = match&.[](index)
        raise ArgumentError, "Invalid controller command" unless value.is_a?(String)

        value
      end

      sig { params(value: T.nilable(String)).returns(String) }
      def required(value)
        raise ArgumentError, "Controller job is malformed" unless value

        value
      end

      sig { params(value: T.nilable(Integer)).returns(Integer) }
      def required_integer(value)
        raise ArgumentError, "Controller job is malformed" unless value

        value
      end
    end
  end
end
