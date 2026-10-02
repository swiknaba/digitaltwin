# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Handles workflow.provision: creates the verified start thread once, binds
    # the workflow and its worktree, and reserves the Writer and Reviewer
    # sessions. An unproved thread post leaves the request uncertain and is
    # never repeated; ReconcileStart settles it from human-verified evidence.
    class Provision
      extend T::Sig
      include Platform::Jobs::Handler

      Code = Dto::ErrorCode
      State = Domains::Workflows::Dto::RequestState
      Decision = Platform::Jobs::Dto::Decision
      Outcome = T.type_alias { Kirei::Services::Result[State] }

      sig do
        params(db: Sequel::Database, source: Domains::Messaging::VerifyHumanSource, api: Adapters::Mattermost::Api, bot_id: String,
               worktrees: Projects::PrepareWorktree, sessions: Domains::Sessions::Lifecycle, policy: Domains::Workflows::Policy,
               directory: Domains::Projects::Directory, requests: Domains::Workflows::Requests, worktree_root: String, master_channel_id: T.nilable(String)).void
      end
      def initialize(db, source:, api:, bot_id:, worktrees:, sessions:, policy: Domains::Workflows::Policy.new, directory: Domains::Projects::Directory.new,
                     requests: Domains::Workflows::Requests.new, worktree_root: ENV.fetch("WORKTREE_ROOT", "/workspace/worktrees"),
                     master_channel_id: ENV["MASTER_CHANNEL_ID"])
        # conversation_bindings stays a raw table until Task 9.
        @db = db
        @source = source
        @api = api
        @bot = bot_id
        @thread_bot = T.let(VerifyThreadBot.new(api: api, bot_id: bot_id), VerifyThreadBot)
        @worktrees = worktrees
        @sessions = sessions
        @policy = policy
        @directory = directory
        @requests = requests
        @worktree_root = worktree_root
        @master_channel = master_channel_id
      end

      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          request_id = Domains::Workflows::Dto::ProvisionJob.from_hash(job.payload, true).request_id
          state = Platform::Unwrap.call(provision(request_id, job.lease))
          next Decision.complete if state == State::Bound

          Decision.block("Provision #{state.serialize}; evidence/reconciliation required")
        end
      end

      sig { params(id: String, lease: Platform::Jobs::Lease).returns(Outcome) }
      private def provision(id, lease)
        Platform::Lock.new.call(key: "provision:#{id}") do
          request = @requests.find(id: id)
          next failure(Code::MissingRequest, "Missing workflow request") unless request
          next success(request.state) unless request.state == State::Queued
          next success(State::Queued) unless @policy.dispatch_allowed?

          project = @directory.find(id: request.project_id)
          next failure(Code::UnknownProject, "Unknown project") unless project

          verified = @source.call(inbox_id: request.inbox_id, destination: project.channel_id)
          next Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

          thread = request.thread_id
          unless thread
            next failure(Code::UnverifiedThreadBot, "Unverified thread bot") unless @thread_bot.call(channel_id: project.channel_id)

            thread = create_thread(request, project, lease)
            next success(State::Uncertain) unless thread
          end
          bind(request, project, thread, verified.result)
        end
      end

      # Returns nil when the post result is unproved; the request is then uncertain.
      sig { params(request: Domains::Workflows::Dto::RequestView, project: Domains::Projects::Dto::Project, lease: Platform::Jobs::Lease).returns(T.nilable(String)) }
      private def create_thread(request, project, lease)
        @requests.mark(id: request.id, state: State::Sending, reason: nil)
        begin
          raise IOError, "Dispatch lease lost" unless lease.begin_effect

          title = request.parameters.title
          post = @api.create_post(Adapters::Mattermost::Dto::NewPost.new(channel_id: project.channel_id, root_id: "", message: title,
                                                                         props: { "digitaltwin_workflow_request" => request.id }))
          valid = post.id.match?(/\A[a-z0-9]{26}\z/) && post.channel_id == project.channel_id
          valid &&= post.root_id.to_s.empty? && post.user_id == @bot && post.message == title
          valid &&= post.props["digitaltwin_workflow_request"] == request.id
          raise IOError, "Unverified created thread" unless valid

          @requests.record_thread(id: request.id, thread_id: post.id)
          post.id
        rescue StandardError
          # Any failure after the post may have started is an uncertain effect.
          @requests.mark(id: request.id, state: State::Uncertain, reason: "Thread creation requires reconciliation; do not repeat")
          nil
        end
      end

      sig do
        params(request: Domains::Workflows::Dto::RequestView, project: Domains::Projects::Dto::Project, thread: String,
               delivery: Domains::Messaging::Dto::VerifiedDelivery).returns(Outcome)
      end
      private def bind(request, project, thread, delivery)
        bound = Platform::Transaction.new.call do
          draft = Domains::Workflows::Dto::WorkflowDraft.new(project_id: project.id, channel_id: project.channel_id, thread_id: thread, worktree_root: @worktree_root,
                                                             source_inbox_id: request.inbox_id, role_configurations: request.parameters.roles)
          result = @requests.bind(id: request.id, workflow: draft)
          bind_conversations(result.result, request, delivery) if result.success? && request.workflow_id.nil?
          result
        end
        return Kirei::Services::Result.new(errors: bound.errors) if bound.failed?

        workflow = bound.result
        prepared = @worktrees.call(slug: project.slug, workflow_id: workflow.id, branch: workflow.branch)
        return Kirei::Services::Result.new(errors: prepared.errors) if prepared.failed?
        return failure(Code::WorktreeChanged, "Worktree binding changed") unless prepared.result == workflow.worktree_path

        @sessions.reserve(workflow_id: workflow.id, role: "writer")
        @sessions.reserve(workflow_id: workflow.id, role: "reviewer")
        @requests.mark(id: request.id, state: State::Bound, reason: nil)
        success(State::Bound)
      end

      # A new workflow becomes the human's current conversation context, and in
      # the Master channel also the context of later top-level posts.
      sig { params(workflow: Domains::Workflows::Dto::WorkflowView, request: Domains::Workflows::Dto::RequestView, delivery: Domains::Messaging::Dto::VerifiedDelivery).void }
      private def bind_conversations(workflow, request, delivery)
        threads = [delivery.thread_id]
        threads << "master" if delivery.root_post && delivery.channel_id == @master_channel
        threads.each do |context_thread|
          values = { workflow_id: workflow.id, inbox_id: request.inbox_id, updated_at: Time.now }
          @db[:conversation_bindings].insert_conflict(target: %i[channel_id thread_id user_id], update: values)
                                     .insert(**values, channel_id: delivery.channel_id, thread_id: context_thread, user_id: delivery.actor.user_id)
        end
      end

      sig { params(state: State).returns(Outcome) }
      private def success(state) = Kirei::Services::Result.new(result: state)

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
