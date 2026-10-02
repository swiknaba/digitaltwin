# typed: strict
# frozen_string_literal: true

module Controllers
  module Requests
    class ReviewCallback < T::Struct
      const :token, String
      const :generation, Integer
      const :verdict, String
      const :commit, String
    end
  end
end
