# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # `@<agent> recover-followup <followup_id> delivered|discard`.
      class RecoverFollowup < T::Struct
        include Kirei::Domain::ValueObject

        const :followup_id, Integer
        const :outcome, FollowupOutcome
      end
    end
  end
end
