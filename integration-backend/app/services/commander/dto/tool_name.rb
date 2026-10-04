# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    module Dto
      # A request-bound Commander tool. Declaration order is the manifest order.
      class ToolName < T::Enum
        extend T::Sig

        enums do
          ListProjects = new("list_projects")
          ListWorkflows = new("list_workflows")
          ReadContext = new("read_context")
          StartWorkflow = new("start_workflow")
          SendPrompt = new("send_prompt")
          WorkflowControl = new("workflow_control")
        end

        # The required input fields besides request_id, in manifest order.
        sig { returns(T::Array[ToolField]) }
        def fields
          case self
          when ListProjects, ListWorkflows, ReadContext then []
          when StartWorkflow then [ToolField::ProjectId, ToolField::Title]
          when SendPrompt then [ToolField::WorkflowId, ToolField::EvidenceInboxIds]
          when WorkflowControl then [ToolField::WorkflowId, ToolField::Action, ToolField::ExpectedVersion]
          else T.absurd(self)
          end
        end
      end
    end
  end
end
