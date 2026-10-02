# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # An artifact gate. Spec and plan gates end in a human approval.
      class Gate < T::Enum
        extend T::Sig

        enums do
          Spec = new("spec")
          Plan = new("plan")
          Implementation = new("implementation")
        end

        sig { returns(Phase) }
        def writing_phase
          case self
          when Spec then Phase::SpecWriting
          when Plan then Phase::PlanWriting
          when Implementation then Phase::Implementation
          else T.absurd(self)
          end
        end

        sig { returns(Phase) }
        def review_phase
          case self
          when Spec then Phase::SpecReview
          when Plan then Phase::PlanReview
          when Implementation then Phase::ImplementationReview
          else T.absurd(self)
          end
        end

        sig { returns(T.nilable(Phase)) }
        def human_approval_phase
          case self
          when Spec then Phase::SpecHumanApproval
          when Plan then Phase::PlanHumanApproval
          when Implementation then nil
          else T.absurd(self)
          end
        end

        # Gates whose approvals must still hold before work after this gate.
        sig { returns(T::Array[Gate]) }
        def approved_gates
          case self
          when Spec then [Spec]
          when Plan then [Spec, Plan]
          when Implementation then []
          else T.absurd(self)
          end
        end
      end
    end
  end
end
