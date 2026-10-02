# typed: strict
# frozen_string_literal: true

module Services
  module Master
    module Dto
      # The typed result of one Master tool; send_prompt returns a RouteOutcome.
      ToolResponse = T.type_alias { T.any(ProjectList, WorkflowList, ContextList, StartReceipt, RouteOutcome, ControlReceipt) }
    end
  end
end
