# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    module Dto
      # Audit details of a verified review prompt reconciliation.
      class ReviewReceiptAudit < T::Struct
        include Kirei::Domain::ValueObject

        const :review_id, Integer
        const :target_commit, String
        const :review_commit, String
        const :session_id, String
        const :generation, Integer
      end
    end
  end
end
