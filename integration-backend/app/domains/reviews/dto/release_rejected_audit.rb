# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    module Dto
      # Audit details of a queued message whose source was rejected at release.
      class ReleaseRejectedAudit < T::Struct
        include Kirei::Domain::ValueObject

        const :workflow_id, String
        const :inbox_id, String
      end
    end
  end
end
