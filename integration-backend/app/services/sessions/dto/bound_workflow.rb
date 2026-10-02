# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    module Dto
      # The workflow fields that PostWorkerChat checks.
      class BoundWorkflow < T::Struct
        include Kirei::Domain::ValueObject

        const :channel_id, String
        const :thread_id, String
        const :phase, String
        const :saved_phase, T.nilable(String)
        const :archived_at, T.nilable(Time)
      end
    end
  end
end
