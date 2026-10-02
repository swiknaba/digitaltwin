# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # Workflow actions a human addresses to the Worker bot.
      class WorkerAction < T::Enum
        enums do
          Start = new("start")
          Approve = new("approve")
          Pause = new("pause")
          Resume = new("resume")
          Finish = new("finish")
          Cancel = new("cancel")
        end
      end
    end
  end
end
