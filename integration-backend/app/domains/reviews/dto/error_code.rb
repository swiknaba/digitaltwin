# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    module Dto
      # Expected failure codes of the reviews domain.
      class ErrorCode < T::Enum
        enums do
          RoundsExhausted = new("rounds_exhausted")
          MissingReview = new("missing_review")
          AlreadyDecided = new("already_decided")
        end
      end
    end
  end
end
