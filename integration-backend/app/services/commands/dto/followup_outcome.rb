# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # Human outcome for an uncertain follow-up send.
      class FollowupOutcome < T::Enum
        enums do
          Delivered = new("delivered")
          Discard = new("discard")
        end
      end
    end
  end
end
