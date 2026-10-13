# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    module Dto
      # Persisted job kind strings; values are part of the durable queue contract.
      class JobKind < T::Enum
        enums do
          FutureTaskDue = new("future_task.due")
          FutureTaskReconcile = new("future_task.reconcile")
        end
      end
    end
  end
end
