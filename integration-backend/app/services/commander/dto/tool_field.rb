# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    module Dto
      # A Commander tool input field besides request_id. The value is its JSON key.
      class ToolField < T::Enum
        extend T::Sig

        enums do
          ProjectId = new("project_id")
          Title = new("title")
          WorkflowId = new("workflow_id")
          EvidenceInboxIds = new("evidence_inbox_ids")
          Action = new("action")
          ExpectedVersion = new("expected_version")
        end

        # The JSON Schema type of the tool manifest.
        sig { returns(String) }
        def json_type
          case self
          when ProjectId, Title, WorkflowId, Action then "string"
          when EvidenceInboxIds then "array"
          when ExpectedVersion then "integer"
          else T.absurd(self)
          end
        end
      end
    end
  end
end
