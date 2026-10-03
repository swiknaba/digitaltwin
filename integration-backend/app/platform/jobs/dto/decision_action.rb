# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    module Dto
      class DecisionAction < T::Enum
        enums do
          Complete = new("complete")
          Defer = new("defer")
          Block = new("block")
        end
      end
    end
  end
end
