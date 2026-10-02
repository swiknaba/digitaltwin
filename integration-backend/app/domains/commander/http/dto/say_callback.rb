# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
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
end
