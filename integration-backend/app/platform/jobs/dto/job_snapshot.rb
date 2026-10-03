# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    module Dto
      # Read-only job state for reconciliation checks outside the worker.
      class JobSnapshot < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :status, JobStatus
        const :lease_expires_at, T.nilable(Time)
        const :effect_started_at, T.nilable(Time)
      end
    end
  end
end
