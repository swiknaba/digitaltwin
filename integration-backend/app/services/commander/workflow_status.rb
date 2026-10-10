# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    # Builds Commander status exclusively from durable records. Runtime state is
    # deliberately the last verified session state, never a claimed live value.
    class WorkflowStatus
      extend T::Sig

      Request = Domains::Commander::Dto::CommanderRequestView
      Workflow = Domains::Workflows::Dto::WorkflowView

      sig do
        params(source: Domains::Messaging::VerifyHumanSource, directory: Domains::Projects::Directory, catalog: Domains::Workflows::Catalog,
               sessions: Domains::Sessions::Registry, reviews: Domains::Reviews::Rounds, approvals: Domains::Workflows::Approvals).void
      end
      def initialize(source:, directory: Domains::Projects::Directory.new, catalog: Domains::Workflows::Catalog.new,
                     sessions: Domains::Sessions::Registry.new, reviews: Domains::Reviews::Rounds.new, approvals: Domains::Workflows::Approvals.new)
        @source = source
        @directory = directory
        @catalog = catalog
        @sessions = sessions
        @reviews = reviews
        @approvals = approvals
      end

      sig { params(request: Request).returns(Dto::WorkflowStatusList) }
      def call(request:)
        Dto::WorkflowStatusList.new(workflows: @catalog.active.filter_map { |workflow| status(request, workflow) })
      end

      sig { params(request: Request, workflow: Workflow).returns(T.nilable(Dto::WorkflowStatus)) }
      private def status(request, workflow)
        return nil if @source.call(inbox_id: request.inbox_id, destination: workflow.channel_id).failed?

        project = @directory.find(id: workflow.project_id)
        return nil unless project

        session = @sessions.active(workflow_id: workflow.id, role: nil).max_by { |candidate| candidate.last_verified_at || Time.at(0) }
        review = review(workflow)
        Dto::WorkflowStatus.new(
          project_id: project.id, project_slug: project.slug, workflow_id: workflow.id, thread_id: workflow.thread_id,
          phase: workflow.phase.serialize, wait_reason: wait_reason(workflow), session_state: session&.state&.serialize,
          last_verified_at: session&.last_verified_at, review_state: review&.dispatch_state&.serialize,
          approval_state: approval_state(workflow), delivery_state: nil, artifact_links: artifact_links(workflow)
        )
      end

      sig { params(workflow: Workflow).returns(T.nilable(Domains::Reviews::Dto::ReviewView)) }
      private def review(workflow)
        gate = gate_for(workflow.effective_phase)
        gate && @reviews.latest(workflow_id: workflow.id, gate: gate)
      end

      sig { params(workflow: Workflow).returns(T.nilable(String)) }
      private def approval_state(workflow)
        gate = gate_for(workflow.effective_phase)
        return nil unless gate && workflow.effective_phase&.human_approval?

        artifact = workflow.artifacts.fetch(gate)
        artifact && @approvals.find(workflow_id: workflow.id, gate: gate, commit: artifact.commit) ? "recorded" : "required"
      end

      sig { params(phase: T.nilable(Domains::Workflows::Dto::Phase)).returns(T.nilable(Domains::Workflows::Dto::Gate)) }
      private def gate_for(phase)
        case phase
        when Domains::Workflows::Dto::Phase::SpecReview, Domains::Workflows::Dto::Phase::SpecHumanApproval then Domains::Workflows::Dto::Gate::Spec
        when Domains::Workflows::Dto::Phase::PlanReview, Domains::Workflows::Dto::Phase::PlanHumanApproval then Domains::Workflows::Dto::Gate::Plan
        when Domains::Workflows::Dto::Phase::ImplementationReview, Domains::Workflows::Dto::Phase::PrReady then Domains::Workflows::Dto::Gate::Implementation
        else nil
        end
      end

      sig { params(workflow: Workflow).returns(T.nilable(String)) }
      private def wait_reason(workflow)
        return workflow.blocker if workflow.blocker
        return "Paused before the next step" if workflow.phase == Domains::Workflows::Dto::Phase::Paused
        return "Waiting for human approval" if workflow.effective_phase&.human_approval?
        return "Waiting for review" if workflow.effective_phase&.review?

        nil
      end

      sig { params(workflow: Workflow).returns(T::Array[String]) }
      private def artifact_links(workflow)
        [workflow.artifacts.spec, workflow.artifacts.plan, workflow.artifacts.implementation].compact.map do |artifact|
          artifact.path || artifact.commit
        end
      end
    end
  end
end
