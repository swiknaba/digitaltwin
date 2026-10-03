# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # `@<agent> approve <workflow_id> spec|plan <40-hex commit>`.
      class Approve < T::Struct
        include Kirei::Domain::ValueObject

        const :workflow_id, String
        const :gate, ApprovalGate
        const :commit, String
      end
    end
  end
end
