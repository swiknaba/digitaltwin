# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # Audit details of a verified workflow control action.
      class WorkflowControlAudit < T::Struct
        include Kirei::Domain::ValueObject

        const :inbox_id, String
        const :workflow_id, String
        const :version, Integer
      end
    end
  end
end
