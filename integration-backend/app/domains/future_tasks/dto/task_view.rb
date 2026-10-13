# typed: strict
# frozen_string_literal: true

module Domains
  module FutureTasks
    module Dto
      class TaskView < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :actor_id, String
        const :origin, String
        const :text, String
        const :references, T::Array[String]
        const :timezone, String
        const :local_time, String
        const :recurrence, T.nilable(String), default: nil
        const :due_at, Time
        const :version, Integer
        const :state, TaskState
        const :execution_id, String
        const :delivery_key, String
        const :receipt, T.nilable(DeliveryReceipt), default: nil
      end
    end
  end
end
