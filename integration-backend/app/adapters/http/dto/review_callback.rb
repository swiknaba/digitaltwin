# typed: strict
# frozen_string_literal: true

module Adapters
  module Http
    module Dto
      class ReviewCallback < T::Struct
        const :token, String
        const :generation, Integer
        const :verdict, String
        const :commit, String
      end
    end
  end
end
