# typed: strict
# frozen_string_literal: true

module Domains
  module Memory
    module Dto
      # Expected failures when storing bounded Commander memory.
      class ErrorCode < T::Enum
        enums do
          MissingProject = new("missing_project")
          MissingEntry = new("missing_entry")
          RevisionChanged = new("revision_changed")
          InvalidContent = new("invalid_content")
          InvalidLimit = new("invalid_limit")
          MemoryFull = new("memory_full")
          PersistenceFailed = new("persistence_failed")
        end
      end
    end
  end
end
