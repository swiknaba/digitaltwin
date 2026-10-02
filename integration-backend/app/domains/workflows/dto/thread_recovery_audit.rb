# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # Audit details of a human-verified start-thread reconciliation.
      class ThreadRecoveryAudit < T::Struct
        include Kirei::Domain::ValueObject

        const :inbox_id, Integer
        const :request_id, String
        const :thread_id, String
      end
    end
  end
end
