# typed: strict
# frozen_string_literal: true

module Domains
  module Memory
    module Dto
      # A source-attributed Commander preference, learning, or project decision.
      class MemoryEntry < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :scope, MemoryScope
        const :project_id, T.nilable(String)
        const :content, String
        const :source, String
        const :revision, Integer
        const :created_at, Time
        const :updated_at, Time
      end
    end
  end
end
