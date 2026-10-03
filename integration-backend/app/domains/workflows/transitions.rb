# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    # The only writer of workflow phase, version and artifacts. Each transition
    # holds Platform::Lock keyed by the workflow id, rereads the row, checks the
    # expected version, and writes `version + 1` only if the version still
    # matches. A stale version returns VersionChanged and writes nothing.
    # Callers that queue jobs in the same transaction wrap the call in it.
    class Transitions
      extend T::Sig

      Code = Dto::ErrorCode
      Phase = Dto::Phase
      Action = Dto::ControlAction
      Outcome = T.type_alias { Kirei::Services::Result[Dto::WorkflowView] }
      ArtifactsJson = T.type_alias { T::Hash[String, T::Hash[String, T.nilable(String)]] }
      Changes = T.type_alias { T::Hash[Symbol, T.nilable(T.any(String, Integer, Time, ArtifactsJson))] }
      PAUSE_BLOCKED = T.let([Phase::Paused, Phase::Closed, Phase::Cancelled, Phase::Blocked].freeze, T::Array[Phase])

      sig { params(lock: Platform::Lock, catalog: Catalog).void }
      def initialize(lock: Platform::Lock.new, catalog: Catalog.new)
        @lock = lock
        @catalog = catalog
      end

      # Checks a control command in today's order: version, archive state, then
      # the action's phase rule. It writes nothing.
      sig { params(workflow: Dto::WorkflowView, action: Action, expected_version: Integer).returns(Outcome) }
      def permit_control(workflow:, action:, expected_version:)
        return failure(Code::VersionChanged, "Workflow version changed") unless workflow.version == expected_version
        return failure(Code::Inactive, "Workflow version changed") if workflow.archived_at

        case action
        when Action::Pause
          return failure(Code::CannotPause, "Cannot pause this phase") if PAUSE_BLOCKED.include?(workflow.phase)
        when Action::Resume
          saved = workflow.saved_phase
          return failure(Code::NotPaused, "Not paused") unless workflow.phase == Phase::Paused && saved && saved != Phase::Blocked
        when Action::Finish
          return failure(Code::NotDelivered, "Only delivered workflow may finish") unless workflow.phase == Phase::Done
        when Action::Cancel
          return failure(Code::AlreadyClosed, "Already closed") if workflow.phase.terminal?
        else
          T.absurd(action)
        end
        Kirei::Services::Result.new(result: workflow)
      end

      # Pause saves the phase and the paused commit; resume restores the saved
      # phase and clears both.
      sig { params(workflow_id: String, action: Action, expected_version: Integer, paused_commit: T.nilable(String)).returns(Outcome) }
      def control(workflow_id:, action:, expected_version:, paused_commit: nil)
        locked(workflow_id) do |workflow|
          permitted = permit_control(workflow: workflow, action: action, expected_version: expected_version)
          next permitted if permitted.failed?

          write(workflow, control_changes(workflow, action, paused_commit))
        end
      end

      sig { params(workflow_id: String, gate: Dto::Gate, expected_version: Integer).returns(Outcome) }
      def advance_approval(workflow_id:, gate:, expected_version:)
        locked(workflow_id) do |workflow|
          next failure(Code::PhaseMismatch, "Approval phase mismatch") unless gate.human_approval_phase == workflow.phase
          next failure(Code::VersionChanged, "Workflow version changed") unless workflow.version == expected_version

          write(workflow, { phase: (gate == Dto::Gate::Spec ? Phase::PlanWriting : Phase::Implementation).serialize })
        end
      end

      # Records the gate's artifact and enters its review phase. A paused
      # workflow saves the review phase and the artifact commit instead.
      sig { params(workflow_id: String, gate: Dto::Gate, ref: Dto::ArtifactRef, expected_version: Integer).returns(Outcome) }
      def record_artifact(workflow_id:, gate:, ref:, expected_version:)
        locked(workflow_id) do |workflow|
          next failure(Code::VersionChanged, "Workflow version changed") unless workflow.version == expected_version

          review = gate.review_phase.serialize
          changes = T.let(paused?(workflow) ? { saved_phase: review, paused_commit: ref.commit } : { phase: review }, Changes)
          write(workflow, changes.merge(artifacts: workflow.artifacts.with(gate: gate, ref: ref).serialize))
        end
      end

      # Enters a phase and records the blocker. A paused workflow saves the
      # phase and `paused_commit` instead.
      sig do
        params(workflow_id: String, phase: Phase, expected_version: Integer, paused_commit: T.nilable(String), blocker: T.nilable(String)).returns(Outcome)
      end
      def enter(workflow_id:, phase:, expected_version:, paused_commit:, blocker:)
        locked(workflow_id) do |workflow|
          next failure(Code::VersionChanged, "Workflow version changed") unless workflow.version == expected_version

          changes = T.let(paused?(workflow) ? { saved_phase: phase.serialize, paused_commit: paused_commit } : { phase: phase.serialize }, Changes)
          write(workflow, changes.merge(blocker: blocker))
        end
      end

      # Archiving keeps the version: no transition may follow it.
      sig { params(workflow_id: String).void }
      def archive(workflow_id:)
        @lock.call(key: workflow_id) do
          Entities::Workflow.query.where(id: workflow_id).update(archived_at: Time.now)
        end
      end

      sig { params(workflow_id: String, blk: T.proc.params(workflow: Dto::WorkflowView).returns(Outcome)).returns(Outcome) }
      private def locked(workflow_id, &blk)
        @lock.call(key: workflow_id) do
          workflow = @catalog.find(id: workflow_id)
          next failure(Code::MissingWorkflow, "Missing workflow") unless workflow

          yield(workflow)
        end
      end

      sig { params(workflow: Dto::WorkflowView, action: Action, paused_commit: T.nilable(String)).returns(Changes) }
      private def control_changes(workflow, action, paused_commit)
        case action
        when Action::Pause then { phase: Phase::Paused.serialize, saved_phase: workflow.phase.serialize, paused_commit: paused_commit }
        when Action::Resume then { phase: workflow.saved_phase&.serialize, saved_phase: nil, paused_commit: nil }
        when Action::Finish then { phase: Phase::Closed.serialize }
        when Action::Cancel then { phase: Phase::Cancelled.serialize }
        else T.absurd(action)
        end
      end

      sig { params(workflow: Dto::WorkflowView, changes: Changes).returns(Outcome) }
      private def write(workflow, changes)
        values = changes.merge(version: workflow.version + 1)
        Entities::Workflow.wrap_jsonb_non_primivitives!(values)
        written = Entities::Workflow.query.where(id: workflow.id, version: workflow.version).update(values)
        return failure(Code::VersionChanged, "Workflow version changed") unless written == 1

        Kirei::Services::Result.new(result: T.must(@catalog.find(id: workflow.id)))
      end

      sig { params(workflow: Dto::WorkflowView).returns(T::Boolean) }
      private def paused?(workflow) = workflow.phase == Phase::Paused

      sig { params(code: Code, detail: String).returns(Outcome) }
      private def failure(code, detail)
        Kirei::Services::Result.new(errors: Platform::Failure.call(code: code, detail: detail))
      end
    end
  end
end
