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
      RoleFile = Domains::Workflows::Dto::RoleFile
      Workflows = ::Services::Workflows
      Commands = ::Services::Commands::Dto
      Master = ::Services::Master

      sig { returns(::Services::Master::Tools) }
      attr_reader :tools

      sig { returns(T.nilable(::Services::Master::Reply)) }
      attr_reader :reply

      sig { returns(::Services::Master::RecordApproval) }
      attr_reader :approvals

      sig { returns(::Services::Sessions::ReserveSession) }
      attr_reader :reserve_session

      sig { returns(Workflows::RequestStart) }
      attr_reader :request_start

      sig { returns(Domains::Messaging::VerifyHumanSource) }
      attr_reader :source

      sig { returns(Services) }
      def self.from_env
        url = ENV.fetch("MATTERMOST_URL")
        listener = Adapters::Mattermost::Api.new(client: Adapters::Mattermost::Client.new(url: url, token_file: ENV.fetch("MATTERMOST_LISTENER_TOKEN_FILE")))
        resolver = Adapters::Mattermost::DeliveryVerifier.new(api: listener, local_bot_ids: ENV.fetch("MATTERMOST_LOCAL_BOT_IDS").split(","),
                                                              peer_bot_ids: ENV.fetch("MATTERMOST_PEER_BOT_IDS", "").split(","))
        # Parsed once here; a malformed file fails startup. A controller-only
        # file is valid; starts then fail with RolesMissing.
        roles = ENV["ROLE_CONFIG_FILE"] ? Domains::Workflows::Records.role_file_from_json(File.read(ENV.fetch("ROLE_CONFIG_FILE"))) : nil
        worker = Adapters::Mattermost::Api.new(client: Adapters::Mattermost::Client.new(url: url, token_file: ENV.fetch("MATTERMOST_WORKER_TOKEN_FILE")))
        new(resolver: resolver, membership: listener, api: worker, bot_id: ENV.fetch("MATTERMOST_WORKER_BOT_ID"), roles: roles)
      end

      sig do
        params(resolver: Domains::Messaging::DeliveryVerifier,
               membership: Domains::Messaging::MembershipCheck,
               api: Adapters::Mattermost::Api, bot_id: String, roles: T.nilable(RoleFile),
               policy: Domains::Workflows::Policy, herdr: Adapters::Herdr::Client,
               evidence: Adapters::Git::Evidence, worktrees: T.nilable(::Services::Projects::PrepareWorktree),
               credential_root: String).void
      end
      def initialize(resolver:, membership:, api:, bot_id:, roles:, policy: Domains::Workflows::Policy.new,
                     herdr: Adapters::Herdr::Client.new, evidence: Adapters::Git::Evidence.new,
                     worktrees: nil, credential_root: "/run/herdr/session-credentials")
        revision = Adapters::Git::Revision.new
        current_commit = ->(worktree) { revision.call(worktree_path: worktree.worktree_path, branch: worktree.branch) }
        @source = T.let(Domains::Messaging::VerifyHumanSource.new(verifier: resolver, membership: membership), Domains::Messaging::VerifyHumanSource)
        @approvals = T.let(Master::RecordApproval.new(resolver: resolver, membership: membership, current_commit: current_commit, evidence: evidence),
                           Master::RecordApproval)
        @route_followup = T.let(Master::RouteFollowup.new(resolver: resolver, membership: membership), Master::RouteFollowup)
        @handle_workflow_prompt = T.let(Master::HandleWorkflowPrompt.new(route: @route_followup, approvals: @approvals), Master::HandleWorkflowPrompt)
        credentials = Adapters::Credentials::FileStore.new(root: credential_root)
        @reserve_session = T.let(::Services::Sessions::ReserveSession.new(source: @source, credentials: credentials), ::Services::Sessions::ReserveSession)
        @execute_operation = T.let(::Services::Sessions::ExecuteOperation.new(herdr: herdr, source: @source, credentials: credentials, policy: policy,
                                                                              callback_url: ENV.fetch("DIGITALTWIN_CALLBACK_URL", "http://backend-web:3000")),
                                   ::Services::Sessions::ExecuteOperation)
        @renew = T.let(::Services::Sessions::Renew.new(herdr: herdr, source: @source, credentials: credentials, policy: policy), ::Services::Sessions::Renew)
        @reconcile_operation = T.let(::Services::Sessions::ReconcileOperation.new(herdr: herdr, source: @source, credentials: credentials),
                                     ::Services::Sessions::ReconcileOperation)
        @dispatch_review = T.let(::Services::Reviews::DispatchReview.new(herdr: herdr, evidence: evidence, policy: policy), ::Services::Reviews::DispatchReview)
        @release_queued = T.let(::Services::Reviews::ReleaseQueued.new(route: @route_followup), ::Services::Reviews::ReleaseQueued)
        @apply_callback = T.let(::Services::Reviews::ApplyCallback.new(artifact_ready: ::Services::Reviews::ArtifactReady.new(herdr: herdr, evidence: evidence),
                                                                       review_finished: ::Services::Reviews::ReviewFinished.new(herdr: herdr, evidence: evidence)),
                                ::Services::Reviews::ApplyCallback)
        @advance_approval = T.let(Workflows::AdvanceApproval.new(evidence: evidence), Workflows::AdvanceApproval)
        @request_start = T.let(Workflows::RequestStart.new(source: @source, roles: roles&.assignments), Workflows::RequestStart)
        @reconcile_start = T.let(Workflows::ReconcileStart.new(source: @source, api: api, bot_id: bot_id), Workflows::ReconcileStart)
        @provision = T.let(Workflows::Provision.new(source: @source, api: api, bot_id: bot_id, worktrees: worktrees || ::Services::Projects::PrepareWorktree.new,
                                                    reserve_session: @reserve_session, policy: policy), Workflows::Provision)
        @control = T.let(Workflows::Control.new(source: @source, herdr: herdr, evidence: evidence, stop_sessions: ::Services::Sessions::StopWorkflowSessions.new),
                         Workflows::Control)
        @dispatch_phase_prompt = T.let(Workflows::DispatchPhasePrompt.new(source: @source, herdr: herdr, evidence: evidence, policy: policy),
                                       Workflows::DispatchPhasePrompt)
        @approve_current = T.let(Workflows::ApproveCurrent.new(source: @source, approvals: @approvals, advance: @advance_approval), Workflows::ApproveCurrent)
        @start_existing = T.let(Workflows::StartExisting.new(source: @source, request_start: @request_start), Workflows::StartExisting)
        @tools = T.let(Master::Tools.new(source: @source, authorize: Master::AuthorizeRequest.new(source: @source), request_start: @request_start,
                                         route: @route_followup), Master::Tools)
        controller_role = roles&.controller
        @reply = T.let(controller_role && Master::Reply.new(authorize: Master::AuthorizeRequest.new(source: @source)), T.nilable(Master::Reply))
        @ingest_prompt = T.let(controller_role && Master::IngestPrompt.new(source: @source, bootstrap: ::Services::Sessions::BootstrapController.new(credentials: credentials),
                                                                           configuration: controller_role, credentials: credentials),
                               T.nilable(Master::IngestPrompt))
        @dispatch = T.let(controller_role && Master::Dispatch.new(source: @source, herdr: herdr, credentials: credentials, policy: policy), T.nilable(Master::Dispatch))
        @recover = T.let(controller_role && Master::Recover.new(source: @source, herdr: herdr), T.nilable(Master::Recover))
        @deliver_followup = T.let(Master::DeliverFollowup.new(herdr: herdr, resolver: resolver, membership: membership, policy: policy), Master::DeliverFollowup)
        @reconcile_followup = T.let(Master::ReconcileFollowup.new(herdr: herdr, resolver: resolver, membership: membership), Master::ReconcileFollowup)
      end

      sig { returns(HandlerMap) }
      def handlers
        values = T.let({
                         Kind::MasterPrompt => ->(job) { route(job: job) },
                         Kind::WorkflowPrompt => ->(job) { @handle_workflow_prompt.call(job: job) },
                         Kind::SessionFollowup => ->(job) { @deliver_followup.call(job: job) },
                         Kind::WorkflowProvision => ->(job) { @provision.call(job: job) },
                         Kind::SessionStart => ->(job) { @execute_operation.call(job: job) },
                         Kind::SessionStop => ->(job) { @execute_operation.call(job: job) },
                         Kind::ReviewPrompt => ->(job) { @dispatch_review.call(job: job) },
                         Kind::ReviewRelease => ->(job) { @release_queued.call(job: job) },
                         Kind::ReviewCallback => ->(job) { @apply_callback.call(job: job) },
                         Kind::MasterControl => ->(job) { @control.call(job: job) },
                         Kind::SessionRenew => ->(job) { @renew.call(job: job) },
                         Kind::WorkflowPhasePrompt => ->(job) { @dispatch_phase_prompt.call(job: job) },
                         Kind::WorkflowStart => ->(job) { @start_existing.call(job: job) },
                         Kind::WorkflowPause => ->(job) { @control.call(job: job) },
                         Kind::WorkflowResume => ->(job) { @control.call(job: job) },
                         Kind::WorkflowFinish => ->(job) { @control.call(job: job) },
                         Kind::WorkflowCancel => ->(job) { @control.call(job: job) },
                         Kind::WorkflowApprove => ->(job) { @approve_current.call(job: job) }
                       }, T::Hash[Platform::Jobs::Dto::JobKind, Platform::Jobs::CallableHandler::Callable])
        dispatch = @dispatch
        values[Kind::MasterDispatch] = ->(job) { dispatch.call(job: job) } if dispatch
        values.transform_values { |callable| Platform::Jobs::CallableHandler.new(callable) }
      end

      sig { params(job: ClaimedJob).returns(Decision) }
      def route(job:)
        id = Dto::InboxDispatchJob.from_hash(job.payload, true).inbox_id
        command = parse(human(id).body)
        case command
        when Commands::RecoverStart
          Platform::Unwrap.call(@reconcile_start.call(request_id: command.request_id, inbox_id: id, thread_id: command.thread_id))
          return Decision.complete
        when Commands::RecoverSession
          Platform::Unwrap.call(@reconcile_operation.call(operation_id: command.operation_id, inbox_id: id, pane_id: command.pane_id))
          return Decision.complete
        when Commands::RecoverFollowup
          Platform::Unwrap.call(@reconcile_followup.call(id: command.followup_id, inbox_id: id, outcome: command.outcome))
          return Decision.complete
        when Commands::RecoverMaster
          recover = @recover
          raise ArgumentError, "Master not configured" unless recover

          Platform::Unwrap.call(recover.call(request_id: command.request_id, inbox_id: id))
          return Decision.complete
        when Commands::Approve, Commands::Route, Commands::MalformedDirective
          nil
        when Commands::WorkerCommand, NilClass
          ingest = @ingest_prompt
          if ingest
            Platform::Unwrap.call(ingest.call(inbox_id: id))
            return Decision.complete
          end
        else
          T.absurd(command)
        end
        @handle_workflow_prompt.call(job: job)
        # Exact approvals advance only through the coordinator's independent
        # revision/gate validation. Normal contextual prompts keep their session.
        approval = parse(human(id).body)
        if approval.is_a?(Commands::Approve)
          Platform::Unwrap.call(@advance_approval.call(workflow_id: approval.workflow_id, gate: Domains::Workflows::Dto::Gate.deserialize(approval.gate.serialize)))
        end
        Decision.complete
      end

      sig { params(inbox_id: String).returns(Domains::Messaging::Dto::VerifiedDelivery) }
      private def human(inbox_id)
        Platform::Unwrap.call(@source.call(inbox_id: inbox_id))
      end

      sig { params(body: String).returns(T.nilable(Commands::Command)) }
      private def parse(body)
        ::Services::Commands::Parser.new.call(body: body, agent_handle: ENV.fetch("AGENT_HANDLE", "agent"), worker_handle: ENV.fetch("WORKER_HANDLE", "worker"))
      end
    end
  end
end
