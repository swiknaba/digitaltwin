# typed: strict
# frozen_string_literal: true

module Services
  # Composition root: builds the adapters and use cases from one
  # Configuration. Each reader builds its object on first use and then
  # reuses it, so a process needs only the variables of the objects it uses.
  # A missing required variable raises KeyError, as ENV.fetch did.
  class Composition
    extend T::Sig

    Bot = Domains::Messaging::Dto::Bot
    Mattermost = Adapters::Mattermost
    CREDENTIAL_ROOT = "/run/herdr/session-credentials"

    @instance = T.let(nil, T.nilable(Composition))

    # Process-wide composition built from the environment on first use.
    sig { returns(Composition) }
    def self.instance
      @instance ||= new(configuration: Configuration.from_env)
    end

    sig { returns(Configuration) }
    attr_reader :configuration

    sig { params(configuration: Configuration).void }
    def initialize(configuration:)
      @configuration = configuration
      @listener_client = T.let(nil, T.nilable(Mattermost::Client))
      @listener_api = T.let(nil, T.nilable(Mattermost::Api))
      @verifier = T.let(nil, T.nilable(Mattermost::DeliveryVerifier))
      @worker_api = T.let(nil, T.nilable(Mattermost::Api))
      @herdr = T.let(nil, T.nilable(Adapters::Herdr::Client))
      @revision = T.let(nil, T.nilable(Adapters::Git::Revision))
      @evidence = T.let(nil, T.nilable(Adapters::Git::Evidence))
      @credentials = T.let(nil, T.nilable(Adapters::Credentials::FileStore))
      @policy = T.let(nil, T.nilable(Domains::Workflows::Policy))
      @source = T.let(nil, T.nilable(Domains::Messaging::VerifyHumanSource))
      @authorize_request = T.let(nil, T.nilable(Master::AuthorizeRequest))
      @approvals = T.let(nil, T.nilable(Master::RecordApproval))
      @route_followup = T.let(nil, T.nilable(Master::RouteFollowup))
      @handle_workflow_prompt = T.let(nil, T.nilable(Master::HandleWorkflowPrompt))
      @handle_master_prompt = T.let(nil, T.nilable(Master::HandleMasterPrompt))
      @deliver_followup = T.let(nil, T.nilable(Master::DeliverFollowup))
      @reconcile_followup = T.let(nil, T.nilable(Master::ReconcileFollowup))
      @tools = T.let(nil, T.nilable(Master::Tools))
      @reply = T.let(nil, T.nilable(Master::Reply))
      @ingest_prompt = T.let(nil, T.nilable(Master::IngestPrompt))
      @dispatch = T.let(nil, T.nilable(Master::Dispatch))
      @recover = T.let(nil, T.nilable(Master::Recover))
      @reserve_session = T.let(nil, T.nilable(Sessions::ReserveSession))
      @execute_operation = T.let(nil, T.nilable(Sessions::ExecuteOperation))
      @renew = T.let(nil, T.nilable(Sessions::Renew))
      @reconcile_operation = T.let(nil, T.nilable(Sessions::ReconcileOperation))
      @dispatch_review = T.let(nil, T.nilable(Reviews::DispatchReview))
      @release_queued = T.let(nil, T.nilable(Reviews::ReleaseQueued))
      @apply_callback = T.let(nil, T.nilable(Reviews::ApplyCallback))
      @advance_approval = T.let(nil, T.nilable(Workflows::AdvanceApproval))
      @request_start = T.let(nil, T.nilable(Workflows::RequestStart))
      @reconcile_start = T.let(nil, T.nilable(Workflows::ReconcileStart))
      @prepare_worktree = T.let(nil, T.nilable(Projects::PrepareWorktree))
      @provision = T.let(nil, T.nilable(Workflows::Provision))
      @control = T.let(nil, T.nilable(Workflows::Control))
      @dispatch_phase_prompt = T.let(nil, T.nilable(Workflows::DispatchPhasePrompt))
      @approve_current = T.let(nil, T.nilable(Workflows::ApproveCurrent))
      @start_existing = T.let(nil, T.nilable(Workflows::StartExisting))
      @deliver_outbox = T.let(nil, T.nilable(Outbound::DeliverOutbox))
      @chat_listener = T.let(nil, T.nilable(Inbound::ChatListener))
    end

    sig { returns(Domains::Messaging::VerifyHumanSource) }
    def source
      @source ||= Domains::Messaging::VerifyHumanSource.new(verifier: verifier, membership: listener_api)
    end

    sig { returns(Master::RecordApproval) }
    def approvals
      @approvals ||= begin
        revision = git_revision
        current_commit = ->(worktree) { revision.call(worktree_path: worktree.worktree_path, branch: worktree.branch) }
        Master::RecordApproval.new(resolver: verifier, membership: listener_api, current_commit: current_commit, handle: @configuration.agent_handle,
                                   worker_handle: @configuration.worker_handle, evidence: evidence)
      end
    end

    sig { returns(Master::RouteFollowup) }
    def route_followup
      @route_followup ||= Master::RouteFollowup.new(resolver: verifier, membership: listener_api, handle: @configuration.agent_handle,
                                                    master_channel_id: @configuration.master_channel_id)
    end

    sig { returns(Master::HandleWorkflowPrompt) }
    def handle_workflow_prompt
      @handle_workflow_prompt ||= Master::HandleWorkflowPrompt.new(route: route_followup, approvals: approvals, handle: @configuration.agent_handle,
                                                                   worker_handle: @configuration.worker_handle)
    end

    sig { returns(Master::HandleMasterPrompt) }
    def handle_master_prompt
      @handle_master_prompt ||= Master::HandleMasterPrompt.new(
        source: source, reconcile_start: reconcile_start, reconcile_operation: reconcile_operation, reconcile_followup: reconcile_followup,
        recover: recover, ingest_prompt: ingest_prompt, handle_workflow_prompt: handle_workflow_prompt, advance_approval: advance_approval,
        agent_handle: @configuration.agent_handle, worker_handle: @configuration.worker_handle
      )
    end

    sig { returns(Master::DeliverFollowup) }
    def deliver_followup
      @deliver_followup ||= Master::DeliverFollowup.new(herdr: herdr, resolver: verifier, membership: listener_api, handle: @configuration.agent_handle,
                                                        policy: policy)
    end

    sig { returns(Master::ReconcileFollowup) }
    def reconcile_followup
      @reconcile_followup ||= Master::ReconcileFollowup.new(herdr: herdr, resolver: verifier, membership: listener_api, handle: @configuration.agent_handle)
    end

    sig { returns(Master::Tools) }
    def tools
      @tools ||= Master::Tools.new(source: source, authorize: authorize_request, request_start: request_start, route: route_followup)
    end

    # Nil unless ROLE_CONFIG_FILE configures a controller role.
    sig { returns(T.nilable(Master::Reply)) }
    def reply
      return nil unless controller_role

      @reply ||= Master::Reply.new(authorize: authorize_request)
    end

    # Nil unless ROLE_CONFIG_FILE configures a controller role.
    sig { returns(T.nilable(Master::IngestPrompt)) }
    def ingest_prompt
      role = controller_role
      return nil unless role

      @ingest_prompt ||= Master::IngestPrompt.new(source: source, bootstrap: Sessions::BootstrapController.new(credentials: credentials),
                                                  configuration: role, credentials: credentials)
    end

    # Nil unless ROLE_CONFIG_FILE configures a controller role.
    sig { returns(T.nilable(Master::Dispatch)) }
    def dispatch
      return nil unless controller_role

      @dispatch ||= Master::Dispatch.new(source: source, herdr: herdr, credentials: credentials, policy: policy)
    end

    # Nil unless ROLE_CONFIG_FILE configures a controller role.
    sig { returns(T.nilable(Master::Recover)) }
    def recover
      return nil unless controller_role

      @recover ||= Master::Recover.new(source: source, herdr: herdr, handle: @configuration.agent_handle)
    end

    sig { returns(Sessions::ReserveSession) }
    def reserve_session
      @reserve_session ||= Sessions::ReserveSession.new(source: source, credentials: credentials)
    end

    sig { returns(Sessions::ExecuteOperation) }
    def execute_operation
      @execute_operation ||= Sessions::ExecuteOperation.new(herdr: herdr, source: source, credentials: credentials, policy: policy,
                                                            callback_url: @configuration.callback_url)
    end

    sig { returns(Sessions::Renew) }
    def renew
      @renew ||= Sessions::Renew.new(herdr: herdr, source: source, credentials: credentials, policy: policy)
    end

    sig { returns(Sessions::ReconcileOperation) }
    def reconcile_operation
      @reconcile_operation ||= Sessions::ReconcileOperation.new(herdr: herdr, source: source, credentials: credentials, handle: @configuration.agent_handle)
    end

    sig { returns(Reviews::DispatchReview) }
    def dispatch_review
      @dispatch_review ||= Reviews::DispatchReview.new(herdr: herdr, evidence: evidence, policy: policy)
    end

    sig { returns(Reviews::ReleaseQueued) }
    def release_queued
      @release_queued ||= Reviews::ReleaseQueued.new(route: route_followup)
    end

    sig { returns(Reviews::ApplyCallback) }
    def apply_callback
      @apply_callback ||= Reviews::ApplyCallback.new(artifact_ready: Reviews::ArtifactReady.new(herdr: herdr, evidence: evidence),
                                                     review_finished: Reviews::ReviewFinished.new(herdr: herdr, evidence: evidence))
    end

    sig { returns(Workflows::AdvanceApproval) }
    def advance_approval
      @advance_approval ||= Workflows::AdvanceApproval.new(evidence: evidence)
    end

    sig { returns(Workflows::RequestStart) }
    def request_start
      @request_start ||= Workflows::RequestStart.new(source: source, roles: @configuration.roles&.assignments)
    end

    sig { returns(Workflows::ReconcileStart) }
    def reconcile_start
      @reconcile_start ||= Workflows::ReconcileStart.new(source: source, api: worker_api, bot_id: worker_bot_id, agent_handle: @configuration.agent_handle)
    end

    sig { returns(Projects::PrepareWorktree) }
    def prepare_worktree
      @prepare_worktree ||= Projects::PrepareWorktree.new(
        paths: Domains::Projects::WorkspacePaths.new(root: @configuration.workspace_root, worktrees_root: @configuration.worktree_root)
      )
    end

    sig { returns(Workflows::Provision) }
    def provision
      @provision ||= Workflows::Provision.new(source: source, api: worker_api, bot_id: worker_bot_id, worktrees: prepare_worktree,
                                              reserve_session: reserve_session, worktree_root: @configuration.worktree_root,
                                              master_channel_id: @configuration.master_channel_id, policy: policy)
    end

    sig { returns(Workflows::Control) }
    def control
      @control ||= Workflows::Control.new(source: source, herdr: herdr, evidence: evidence, stop_sessions: Sessions::StopWorkflowSessions.new,
                                          worker_handle: @configuration.worker_handle)
    end

    sig { returns(Workflows::DispatchPhasePrompt) }
    def dispatch_phase_prompt
      @dispatch_phase_prompt ||= Workflows::DispatchPhasePrompt.new(source: source, herdr: herdr, evidence: evidence, policy: policy)
    end

    sig { returns(Workflows::ApproveCurrent) }
    def approve_current
      @approve_current ||= Workflows::ApproveCurrent.new(source: source, approvals: approvals, advance: advance_approval)
    end

    sig { returns(Workflows::StartExisting) }
    def start_existing
      @start_existing ||= Workflows::StartExisting.new(source: source, request_start: request_start, agent_handle: @configuration.agent_handle,
                                                       worker_handle: @configuration.worker_handle)
    end

    # Needs MATTERMOST_<BOT>_TOKEN_FILE and MATTERMOST_<BOT>_BOT_ID for every bot.
    sig { returns(Outbound::DeliverOutbox) }
    def deliver_outbox
      @deliver_outbox ||= begin
        url = mattermost_url
        apis = Bot.values.to_h do |bot|
          token_file = required(@configuration.mattermost_bot_token_files[bot], "MATTERMOST_#{bot.serialize.upcase}_TOKEN_FILE")
          [bot, Mattermost::Api.new(client: Mattermost::Client.new(url: url, token_file: token_file))]
        end
        Outbound::DeliverOutbox.new(apis: apis, bot_ids: Bot.values.to_h { |bot| [bot, bot_id(bot)] })
      end
    end

    sig { returns(Inbound::ChatListener) }
    def chat_listener
      @chat_listener ||= begin
        router = Inbound::RecordDelivery.new(agent_handle: @configuration.agent_handle, worker_handle: @configuration.worker_handle,
                                             master_channel_id: @configuration.master_channel_id)
        Inbound::ChatListener.new(client: listener_client, api: listener_api, verifier: verifier,
                                  channels: required(@configuration.mattermost_channel_ids, "MATTERMOST_CHANNEL_IDS"), router: router,
                                  validation_mode: @configuration.chat_validation_mode, heartbeat_dir: @configuration.heartbeat_dir)
      end
    end

    sig { returns(T.nilable(Domains::Workflows::Dto::RoleConfig)) }
    private def controller_role
      @configuration.roles&.controller
    end

    sig { returns(Master::AuthorizeRequest) }
    private def authorize_request
      @authorize_request ||= Master::AuthorizeRequest.new(source: source)
    end

    sig { returns(String) }
    private def mattermost_url
      required(@configuration.mattermost_url, "MATTERMOST_URL")
    end

    sig { returns(Mattermost::Client) }
    private def listener_client
      @listener_client ||= Mattermost::Client.new(url: mattermost_url,
                                                  token_file: required(@configuration.mattermost_listener_token_file, "MATTERMOST_LISTENER_TOKEN_FILE"))
    end

    sig { returns(Mattermost::Api) }
    private def listener_api
      @listener_api ||= Mattermost::Api.new(client: listener_client)
    end

    sig { returns(Mattermost::DeliveryVerifier) }
    private def verifier
      @verifier ||= Mattermost::DeliveryVerifier.new(api: listener_api,
                                                     local_bot_ids: required(@configuration.mattermost_local_bot_ids, "MATTERMOST_LOCAL_BOT_IDS"),
                                                     peer_bot_ids: @configuration.mattermost_peer_bot_ids)
    end

    sig { returns(Mattermost::Api) }
    private def worker_api
      @worker_api ||= begin
        token_file = required(@configuration.mattermost_bot_token_files[Bot::Worker], "MATTERMOST_WORKER_TOKEN_FILE")
        Mattermost::Api.new(client: Mattermost::Client.new(url: mattermost_url, token_file: token_file))
      end
    end

    sig { returns(String) }
    private def worker_bot_id
      bot_id(Bot::Worker)
    end

    sig { params(bot: Bot).returns(String) }
    private def bot_id(bot)
      required(@configuration.mattermost_bot_ids[bot], "MATTERMOST_#{bot.serialize.upcase}_BOT_ID")
    end

    sig { returns(Adapters::Herdr::Client) }
    private def herdr
      @herdr ||= Adapters::Herdr::Client.new
    end

    sig { returns(Adapters::Git::Revision) }
    private def git_revision
      @revision ||= Adapters::Git::Revision.new(root: @configuration.worktree_root)
    end

    sig { returns(Adapters::Git::Evidence) }
    private def evidence
      @evidence ||= Adapters::Git::Evidence.new(revision: git_revision)
    end

    sig { returns(Adapters::Credentials::FileStore) }
    private def credentials
      @credentials ||= Adapters::Credentials::FileStore.new(root: CREDENTIAL_ROOT)
    end

    sig { returns(Domains::Workflows::Policy) }
    private def policy
      @policy ||= Domains::Workflows::Policy.new
    end

    sig { type_parameters(:Value).params(value: T.nilable(T.type_parameter(:Value)), name: String).returns(T.type_parameter(:Value)) }
    private def required(value, name)
      case value
      when NilClass then raise KeyError, "key not found: #{name.inspect}"
      else value
      end
    end
  end
end
