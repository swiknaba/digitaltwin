# typed: strict
# frozen_string_literal: true

module Domains
  module FutureTasks
    module Dto
      class ExecutionState < T::Enum
        enums do
          Queued = new("queued")
          Claimed = new("claimed")
          Delivering = new("delivering")
          Delivered = new("delivered")
          Failed = new("failed")
          Uncertain = new("uncertain")
          Stale = new("stale")
        end
      end
    end
  end
end
