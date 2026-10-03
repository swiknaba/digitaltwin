# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    # Queues one stop operation per active session of a finished or
    # cancelled workflow, under the workflow lock.
    class StopWorkflowSessions
      extend T::Sig

      sig { params(operations: Domains::Sessions::Operations, lock: Platform::Lock).void }
      def initialize(operations: Domains::Sessions::Operations.new, lock: Platform::Lock.new)
        @operations = operations
        @lock = lock
      end

      sig { params(workflow_id: String).void }
      def call(workflow_id:)
        Kirei::Services::Runner.call(self.class.name.to_s) do
          @lock.call(key: workflow_id) { @operations.queue_stops(workflow_id: workflow_id) }
        end
      end
    end
  end
end
