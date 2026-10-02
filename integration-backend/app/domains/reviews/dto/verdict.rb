# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    module Dto
      class Verdict < T::Enum
        enums do
          Approve = new("approve")
          ChangesRequested = new("changes_requested")
        end
      end
    end
  end
end
