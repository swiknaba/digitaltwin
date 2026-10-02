# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # The `workflows.artifacts` JSONB object: one optional ref per gate. Prop
      # order matches the key order PostgreSQL returns for the stored object.
      class ArtifactSet < T::Struct
        extend T::Sig
        include Kirei::Domain::ValueObject

        const :plan, T.nilable(ArtifactRef), default: nil
        const :spec, T.nilable(ArtifactRef), default: nil
        const :implementation, T.nilable(ArtifactRef), default: nil

        sig { params(gate: Gate).returns(T.nilable(ArtifactRef)) }
        def fetch(gate)
          case gate
          when Gate::Spec then spec
          when Gate::Plan then plan
          when Gate::Implementation then implementation
          else T.absurd(gate)
          end
        end

        sig { params(gate: Gate, ref: ArtifactRef).returns(ArtifactSet) }
        def with(gate:, ref:)
          case gate
          when Gate::Spec then ArtifactSet.new(plan: plan, spec: ref, implementation: implementation)
          when Gate::Plan then ArtifactSet.new(plan: ref, spec: spec, implementation: implementation)
          when Gate::Implementation then ArtifactSet.new(plan: plan, spec: spec, implementation: ref)
          else T.absurd(gate)
          end
        end
      end
    end
  end
end
