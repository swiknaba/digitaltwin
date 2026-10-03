# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # A human workflow control command.
      class ControlAction < T::Enum
        enums do
          Pause = new("pause")
          Resume = new("resume")
          Finish = new("finish")
          Cancel = new("cancel")
        end
      end
    end
  end
end
