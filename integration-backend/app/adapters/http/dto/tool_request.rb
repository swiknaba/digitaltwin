# typed: strict
# frozen_string_literal: true

module Adapters
  module Http
    module Dto
      class ToolRequest < T::Struct
        const :name, String
        const :arguments, T::Hash[String, Object]
      end
    end
  end
end
