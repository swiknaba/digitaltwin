# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    module Dto
      # Status entries visible to the request's authenticated human.
      class WorkflowStatusList < T::Struct
        include Kirei::Domain::ValueObject

        const :workflows, T::Array[WorkflowStatus]
      end
    end
  end
end
