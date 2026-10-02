# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    module Dto
      class JobStatus < T::Enum
        enums do
          Pending = new("pending")
          Running = new("running")
          Complete = new("complete")
          Blocked = new("blocked")
          Uncertain = new("uncertain")
        end
      end
    end
  end
end
