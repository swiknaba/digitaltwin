# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # Artifact gate that a human approves.
      class ApprovalGate < T::Enum
        enums do
          Spec = new("spec")
          Plan = new("plan")
        end
      end
    end
  end
end
