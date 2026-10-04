# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    # Handles human workflow controls: commander.control jobs from the Commander's
    # tool, and workflow.pause/resume/finish/cancel jobs from a thread command.
    # Each control is source-verified and version-bound, and its transition,
    # follow-up jobs, session stops and audit receipt commit together.
    class Control
      extend T::Sig
      include Platform::Jobs::Handler

      Code = Dto::ErrorCode
      Kind = Platform::Jobs::Dto::JobKind
      Action = Domains::Workflows::Dto::ControlAction
      Workflow = Domains::Workflows::Dto::WorkflowView
      Outcome = T.type_alias { Kirei::Services::Result[Workflow] }
      THREAD_ACTIONS = T.let({ Kind::WorkflowPause => Action::Pause, Kind::WorkflowResume => Action::Resume,
                               Kind::WorkflowFinish => Action::Finish, Kind::WorkflowCancel => Action::Cancel }.freeze, T::Hash[Kind, Action])

      sig do
        params(source: Domains::Messaging::VerifyHumanSource, herdr: Adapters::Herdr::Client, evidence: Adapters::Git::Evidence,
               stop_sessions: Sessions::StopWorkflowSessions, worker_handle: String, queue_release: Reviews::QueueRelease, catalog: Domains::Workflows::Catalog,
               transitions: Domains::Workflows::Transitions, phase_prompts: Domains::Workflows::PhasePrompts, audit: Platform::Audit::Log).void
      end
      def initialize(source:, herdr:, evidence:, stop_sessions:, worker_handle:, queue_release: Reviews::QueueRelease.new, catalog: Domains::Workflows::Catalog.new,
                     transitions: Domains::Workflows::Transitions.new,
                     phase_prompts: Domains::Workflows::PhasePrompts.new, audit: Platform::Audit::Log.new)
        @source = source
        @verify_sessions = T.let(VerifySessions.new(herdr: herdr), VerifySessions)
        @evidence = evidence
        @queue_release = queue_release
        @stop_sessions = stop_sessions
        @catalog = catalog
        @transitions = transitions
        @phase_prompts = phase_prompts
        @audit = audit
        @worker = worker_handle
      end

      # Failures raise, so the worker keeps today's retry path.
      sig { override.params(job: Platform::Jobs::Dto::ClaimedJob).returns(Platform::Jobs::Dto::Decision) }
      def call(job:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          Platform::Unwrap.call(job.kind == Kind::CommanderControl ? commander_control(job) : thread_control(job))
          Platform::Jobs::Dto::Decision.complete
        end
      end

      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(Outcome) }
      private def commander_control(job)
        payload = Domains::Commander::Dto::CommanderControlJob.from_hash(job.payload, true)
        action = Action.try_deserialize(payload.action)
        return failure(Code::UnsupportedAction, "Unsupported workflow action") unless action

        control(payload.inbox_id, payload.workflow_id, action, payload.expected_version)
      end

      # The command must come from the workflow's own thread as the exact
      # `@worker <action>` text.
      sig { params(job: Platform::Jobs::Dto::ClaimedJob).returns(Outcome) }
      private def thread_control(job)
        payload = Domains::Commander::Dto::InboxDispatchJob.from_hash(job.payload, true)
        verified = @source.call(inbox_id: payload.inbox_id)
        return Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

        delivery = verified.result
        workflow_id = payload.workflow_id
        return malformed unless workflow_id

        workflow = @catalog.find(id: workflow_id)
        action = THREAD_ACTIONS[job.kind]
        return failure(Code::UnsupportedAction, "Unsupported workflow action") unless action

        same_thread = workflow && delivery.channel_id == workflow.channel_id && delivery.thread_id == workflow.thread_id
        return failure(Code::SourceMismatch, "Control source/workflow mismatch") unless workflow && same_thread && delivery.body == "@#{@worker} #{action.serialize}"

        expected_version = payload.expected_version
        return malformed unless expected_version

        control(payload.inbox_id, workflow.id, action, expected_version)
      end

      sig { params(inbox_id: String, workflow_id: String, action: Action, expected_version: Integer).returns(Outcome) }
      private def control(inbox_id, workflow_id, action, expected_version)
        workflow = @catalog.find(id: workflow_id)
        return failure(Code::MissingWorkflow, "Missing workflow") unless workflow

        verified = @source.call(inbox_id: inbox_id, destination: workflow.channel_id)
        return Kirei::Services::Result.new(errors: verified.errors) if verified.failed?

        Platform::Lock.new.call(key: workflow_id) { locked_control(inbox_id, workflow_id, action, expected_version) }
      end

      # Runs under the workflow lock: checks, then evidence, then one transaction.
      sig { params(inbox_id: String, workflow_id: String, action: Action, expected_version: Integer).returns(Outcome) }
      private def locked_control(inbox_id, workflow_id, action, expected_version)
        workflow = @catalog.find(id: workflow_id)
        return failure(Code::MissingWorkflow, "Missing workflow") unless workflow

        permitted = @transitions.permit_control(workflow: workflow, action: action, expected_version: expected_version)
        return permitted if permitted.failed?

        evidence = evidence_for(workflow, action)
        return Kirei::Services::Result.new(errors: evidence.errors) if evidence.failed?

        paused_commit = action == Action::Pause ? evidence.result : nil
        Platform::Transaction.new.call do
          changed = @transitions.control(workflow_id: workflow_id, action: action, expected_version: expected_version, paused_commit: paused_commit)
          next changed if changed.failed?

          follow_up(changed.result, action, expected_version + 1)
          @audit.record(event_key: "workflow:#{workflow_id}:#{expected_version}:#{action.serialize}", action: action.serialize,
                        details: Domains::Workflows::Dto::WorkflowControlAudit.new(inbox_id: inbox_id, workflow_id: workflow_id, version: expected_version))
          changed
        end
      end

      # Pause records HEAD. Resume needs the live role settled and the paused
      # revision unchanged. Finish and cancel need every session settled.
      sig { params(workflow: Workflow, action: Action).returns(Kirei::Services::Result[String]) }
      private def evidence_for(workflow, action)
        worktree = Adapters::Git::Dto::WorktreeRef.new(worktree_path: workflow.worktree_path, branch: workflow.branch)
        case action
        when Action::Pause
          return Kirei::Services::Result.new(result: @evidence.head(worktree: worktree))
        when Action::Resume
          role = workflow.saved_phase&.review? ? Domains::Sessions::Dto::SessionRole::Reviewer : Domains::Sessions::Dto::SessionRole::Writer
          sessions = @verify_sessions.call(workflow_id: workflow.id, role: role)
          return Kirei::Services::Result.new(errors: sessions.errors) if sessions.failed?
          unless @evidence.current(worktree: worktree) == workflow.paused_commit
            return Kirei::Services::Result.new(errors: Platform::Failure.call(code: Code::PausedRevisionChanged, detail: "Paused revision changed without verified callback"))
          end
        when Action::Finish, Action::Cancel
          sessions = @verify_sessions.call(workflow_id: workflow.id)
          return Kirei::Services::Result.new(errors: sessions.errors) if sessions.failed?
        else
          T.absurd(action)
        end
        Kirei::Services::Result.new(result: action.serialize)
      end

      # A resumed writing phase replaces a still-unstarted prompt with one for
      # the new version. Resume releases queued messages; finish and cancel
      # queue session stops.
      sig { params(workflow: Workflow, action: Action, version: Integer).void }
      private def follow_up(workflow, action, version)
        case action
        when Action::Resume
          @phase_prompts.enqueue(workflow_id: workflow.id, version: version) if workflow.phase.writing? && @phase_prompts.unstarted?(workflow_id: workflow.id)
          @queue_release.call(workflow_id: workflow.id, version: version)
        when Action::Finish, Action::Cancel
          @stop_sessions.call(workflow_id: workflow.id)
        when Action::Pause
          nil
        else
          T.absurd(action)
        end
      end

      sig { returns(Outcome) }
      private def malformed = failure(Code::MalformedJob, "Commander job is malformed")

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
