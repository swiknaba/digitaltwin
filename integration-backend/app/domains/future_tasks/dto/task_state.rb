# typed: strict
# frozen_string_literal: true

module Domains
  module FutureTasks
    module Dto
      class TaskState < T::Enum
        enums do
          Scheduled = new("scheduled")
          Running = new("running")
          AwaitingDisposition = new("awaiting_disposition")
          Completed = new("completed")
          Failed = new("failed")
          Canceled = new("canceled")
          Uncertain = new("uncertain")
        end
      end
    end
  end
end
