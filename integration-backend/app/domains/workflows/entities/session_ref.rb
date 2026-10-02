# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Entities
      class SessionRef < T::Struct
        const :workflow_id, T.nilable(String)
        const :generation, Integer
        const :role, String
        const :pane_id, String
        const :alias, String
      end
    end
  end
end
