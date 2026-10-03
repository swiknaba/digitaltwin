# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # The `workflows.phase` values, as the workflow_phase constraint lists them.
      class Phase < T::Enum
        extend T::Sig

        enums do
          SpecWriting = new("spec_writing")
          SpecReview = new("spec_review")
          SpecHumanApproval = new("spec_human_approval")
          PlanWriting = new("plan_writing")
          PlanReview = new("plan_review")
          PlanHumanApproval = new("plan_human_approval")
          Implementation = new("implementation")
          ImplementationReview = new("implementation_review")
          PrReady = new("pr_ready")
          Done = new("done")
          Closed = new("closed")
          Blocked = new("blocked")
          Paused = new("paused")
          Cancelled = new("cancelled")
        end

        # A phase in which the Writer produces an artifact.
        sig { returns(T::Boolean) }
        def writing? = [SpecWriting, PlanWriting, Implementation].include?(self)

        sig { returns(T::Boolean) }
        def review? = [SpecReview, PlanReview, ImplementationReview].include?(self)

        sig { returns(T::Boolean) }
        def human_approval? = [SpecHumanApproval, PlanHumanApproval].include?(self)

        # Closed and cancelled workflows accept no more work.
        sig { returns(T::Boolean) }
        def terminal? = [Closed, Cancelled].include?(self)
      end
    end
  end
end
