# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # The `followups.evidence` JSONB object: why routing chose the workflow.
      class RoutingEvidence < T::Struct
        extend T::Sig
        include Kirei::Domain::ValueObject

        const :selection, T.nilable(String)
        const :direct_thread, T.nilable(String)
        const :interpretation, T.nilable(RoutingInterpretation)
        const :recent_binding, T.nilable(String)
        const :source_inbox_id, String
        const :attribution, T.nilable(InstructionAttribution), default: nil

        # Keeps today's JSONB shape: absent values stay present as null, and
        # the key order matches what PostgreSQL returns for the stored object.
        # `super` keeps unknown stored keys, so Followups can detect them.
        sig { params(strict: T::Boolean).returns(T::Hash[String, T.nilable(T.any(String, T::Hash[String, T.any(String, T::Array[String])]))]) }
        def serialize(strict = true)
          { "selection" => nil, "direct_thread" => nil, "interpretation" => nil, "recent_binding" => nil, "attribution" => nil }.merge(super)
        end
      end
    end
  end
end
