# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # A Master proposal of the target workflow, grounded in cited inbox ids.
      class RoutingInterpretation < T::Struct
        include Kirei::Domain::ValueObject

        const :workflow_id, String
        const :evidence_inbox_ids, T::Array[String]
      end
    end
  end
end
