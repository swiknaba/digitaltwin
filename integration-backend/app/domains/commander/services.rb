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
      Commands = ::Services::Commands::Dto

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

      sig { returns(Domains::Messaging::VerifyHumanSource) }
      attr_reader :source

      sig { params(db: Sequel::Database).returns(Services) }
      def self.from_env(db)
        url = ENV.fetch("MATTERMOST_URL")
        listener = Adapters::Mattermost::Api.new(client: Adapters::Mattermost::Client.new(url: url, token_file: ENV.fetch("MATTERMOST_LISTENER_TOKEN_FILE")))
        resolver = Adapters::Mattermost::DeliveryVerifier.new(api: listener, local_bot_ids: ENV.fetch("MATTERMOST_LOCAL_BOT_IDS").split(","),
                                                              peer_bot_ids: ENV.fetch("MATTERMOST_PEER_BOT_IDS", "").split(","))
        roles = ENV["ROLE_CONFIG_FILE"] ? JSON.parse(File.read(ENV.fetch("ROLE_CONFIG_FILE"))) : {}
        worker = Adapters::Mattermost::Api.new(client: Adapters::Mattermost::Client.new(url: url, token_file: ENV.fetch("MATTERMOST_WORKER_TOKEN_FILE")))
        new(db, resolver: resolver, membership: listener, api: worker, bot_id: ENV.fetch("MATTERMOST_WORKER_BOT_ID"), roles: roles)
      end

      sig do
        params(db: Sequel::Database, resolver: Domains::Messaging::DeliveryVerifier,
               membership: Domains::Messaging::MembershipCheck,
               api: Adapters::Mattermost::Api, bot_id: String, roles: Roles,
               policy: Domains::Workflows::Policy, herdr: Adapters::Herdr::Client,
               evidence: Adapters::Git::Evidence, worktrees: T.nilable(::Services::Projects::PrepareWorktree),
               credential_root: String).void
      end
      def initialize(db, resolver:, membership:, api:, bot_id:, roles:, policy: Domains::Workflows::Policy.new,
                     herdr: Adapters::Herdr::Client.new, evidence: Adapters::Git::Evidence.new,
                     worktrees: nil, credential_root: "/run/herdr/session-credentials")
        @db = db
        revision = Adapters::Git::Revision.new
        current_commit = ->(worktree) { revision.call(worktree_path: worktree.worktree_path, branch: worktree.branch) }
        @source = T.let(Domains::Messaging::VerifyHumanSource.new(verifier: resolver, membership: membership), Domains::Messaging::VerifyHumanSource)
        # Commander internals still take a membership proc until Task 9.
        member = ->(channel_id, user_id) { membership.member?(channel_id: channel_id, user_id: user_id) }
        @approvals = T.let(Approvals.new(db, resolver: resolver, membership: member, current_commit: current_commit, evidence: evidence), Approvals)
        @routing = T.let(Routing.new(db, resolver: resolver, membership: member, approvals: @approvals), Routing)
        @sessions = T.let(
          Domains::Sessions::Lifecycle.new(db, herdr: herdr, source: @source, credential_root: credential_root,
                                               callback_url: ENV.fetch("DIGITALTWIN_CALLBACK_URL", "http://backend-web:3000"), policy: policy),
          Domains::Sessions::Lifecycle
        )
        @reviews = T.let(Domains::Reviews::Coordinator.new(db, herdr: herdr, evidence: evidence, routing: @routing, policy: policy), Domains::Reviews::Coordinator)
        @workflows = T.let(Domains::Workflows::Coordinator.new(db, source: @source, herdr: herdr, evidence: evidence, reviews: @reviews, sessions: @sessions, policy: policy), Domains::Workflows::Coordinator)
        @provision = T.let(Domains::Workflows::Provision.new(db, source: @source, api: api, bot_id: bot_id,
                                                                 worktrees: worktrees || ::Services::Projects::PrepareWorktree.new, sessions: @sessions, roles: roles, policy: policy), Domains::Workflows::Provision)
        controller_role = roles["controller"]
        @master = T.let(controller_role && Master.new(db, sessions: @sessions, source: @source, herdr: herdr,
                                                          configuration: controller_role, credential_root: credential_root, policy: policy), T.nilable(Master))
        @followups = T.let(Followups.new(db, herdr: herdr, resolver: resolver, membership: member, policy: policy), Followups)
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
        command = parse(human(id).body)
        case command
        when Commands::RecoverStart
          @provision.reconcile(id: command.request_id, inbox_id: id, thread_id: command.thread_id)
          return Decision.complete
        when Commands::RecoverSession
          @sessions.reconcile(operation_id: command.operation_id, inbox_id: id, pane_id: command.pane_id)
          return Decision.complete
        when Commands::RecoverFollowup
          @followups.reconcile(id: command.followup_id, inbox_id: id, outcome: command.outcome.serialize)
          return Decision.complete
        when Commands::RecoverMaster
          raise ArgumentError, "Master not configured" unless @master

          @master.recover(request_id: command.request_id, inbox_id: id)
          return Decision.complete
        when Commands::Approve, Commands::Route, Commands::MalformedDirective
          nil
        when Commands::WorkerCommand, NilClass
          if @master
            @master.ingest(id)
            return Decision.complete
          end
        else
          T.absurd(command)
        end
        @routing.call(job: job)
        # Exact approvals advance only through the coordinator's independent
        # revision/gate validation. Normal contextual prompts keep their session.
        approval = parse(human(id).body)
        @workflows.advance_approval(workflow_id: approval.workflow_id, gate: approval.gate.serialize) if approval.is_a?(Commands::Approve)
        Decision.complete
      end

      sig { params(job: ClaimedJob).returns(Decision) }
      def control_existing(job:)
        payload = Dto::InboxDispatchJob.from_hash(job.payload, true)
        inbox_id = payload.inbox_id
        d = human(inbox_id)
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
        d = human(inbox_id)
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
        d = human(id)
        command = parse(d.body)
        start = command.is_a?(Commands::WorkerCommand) && command.action == Commands::WorkerAction::Start && command.single_space_separator
        raise ArgumentError, "Human root start required" unless d.root_post && start

        project = Domains::Projects::Directory.new.for_channel(channel_id: d.channel_id)
        raise ArgumentError, "Use verified project mapping through Master" unless project

        @provision.request(inbox_id: id, project_id: project.id, title: d.body, existing_thread: d.thread_id)
        Decision.complete
      end

      sig { params(inbox_id: Integer).returns(Domains::Messaging::Dto::VerifiedDelivery) }
      private def human(inbox_id)
        Platform::Unwrap.call(@source.call(inbox_id: inbox_id))
      end

      sig { params(body: String).returns(T.nilable(Commands::Command)) }
      private def parse(body)
        ::Services::Commands::Parser.new.call(body: body, agent_handle: ENV.fetch("AGENT_HANDLE", "agent"), worker_handle: ENV.fetch("WORKER_HANDLE", "worker"))
      end

      sig { params(value: T.nilable(String)).returns(String) }
      private def required(value)
        raise ArgumentError, "Controller job is malformed" unless value

        value
      end

      sig { params(value: T.nilable(Integer)).returns(Integer) }
      private def required_integer(value)
        raise ArgumentError, "Controller job is malformed" unless value

        value
      end
    end
  end
end
