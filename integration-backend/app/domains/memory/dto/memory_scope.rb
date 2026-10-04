# typed: strict
# frozen_string_literal: true

module Domains
  module Memory
    module Dto
      # The durable location that owns a Commander memory entry.
      class MemoryScope < T::Enum
        enums do
          Global = new("global")
          Project = new("project")
        end
      end
    end
  end
end
