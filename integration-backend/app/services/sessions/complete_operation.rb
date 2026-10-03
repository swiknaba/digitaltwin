# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    # Settles a proven session operation. A completed start schedules the
    # credential renewal and, for the Writer, the phase prompt. The last
    # completed stop of a terminal workflow archives it. Callers run this in
    # the transaction that records the session's proven state.
    class CompleteOperation
      extend T::Sig

      Dto = Domains::Sessions::Dto
      Workflow = Domains::Workflows::Dto::WorkflowView

      sig do
        params(registry: Domains::Sessions::Registry, operations: Domains::Sessions::Operations, renewals: Domains::Sessions::Renewals,
               phase_prompts: Domains::Workflows::PhasePrompts, transitions: Domains::Workflows::Transitions).void
      end
      def initialize(registry: Domains::Sessions::Registry.new, operations: Domains::Sessions::Operations.new, renewals: Domains::Sessions::Renewals.new,
                     phase_prompts: Domains::Workflows::PhasePrompts.new, transitions: Domains::Workflows::Transitions.new)
        @registry = registry
        @operations = operations
        @renewals = renewals
        @phase_prompts = phase_prompts
        @transitions = transitions
      end

      sig { params(operation: Dto::OperationView, session: Dto::SessionView, workflow: T.nilable(Workflow)).void }
      def call(operation:, session:, workflow:)
        @operations.mark(id: operation.id, state: Dto::OperationState::Complete)
        start = operation.kind == Dto::OperationKind::Start
        @renewals.schedule(session: T.must(@registry.find(id: session.id))) if start
        return unless workflow

        if start && session.role == Dto::SessionRole::Writer
          @phase_prompts.enqueue(workflow_id: workflow.id, version: workflow.version)
        elsif !start && workflow.phase.terminal? && @registry.active(workflow_id: workflow.id, role: nil).empty?
          @transitions.archive(workflow_id: workflow.id)
        end
      end
    end
  end
end
