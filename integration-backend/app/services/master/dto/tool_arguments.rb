# typed: strict
# frozen_string_literal: true

module Services
  module Master
    module Dto
      # Parsed tool input. `fields` lists every supplied JSON key. A value of
      # the wrong JSON type is nil, and a non-string evidence id is a nil item,
      # so Tools can reject them in its check order.
      class ToolArguments < T::Struct
        include Kirei::Domain::ValueObject

        const :fields, T::Array[String]
        const :request_id, T.nilable(String), default: nil
        const :project_id, T.nilable(String), default: nil
        const :title, T.nilable(String), default: nil
        const :workflow_id, T.nilable(String), default: nil
        const :evidence_inbox_ids, T.nilable(T::Array[T.nilable(String)]), default: nil
        const :action, T.nilable(String), default: nil
        const :expected_version, T.nilable(Integer), default: nil
      end
    end
  end
end
