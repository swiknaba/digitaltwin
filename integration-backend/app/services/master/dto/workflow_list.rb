# typed: strict
# frozen_string_literal: true

module Services
  module Master
    module Dto
      # list_workflows: the active workflows the request's human can access.
      class WorkflowList < T::Struct
        include Kirei::Domain::ValueObject

        const :workflows, T::Array[Domains::Workflows::Dto::WorkflowView]
      end
    end
  end
end
