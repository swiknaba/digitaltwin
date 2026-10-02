# typed: strict
# frozen_string_literal: true

module Adapters
  module Http
    module Dto
      class SayCallback < T::Struct
        const :token, String
        const :generation, Integer
        const :key, String
        const :body, String
      end
    end
  end
end
