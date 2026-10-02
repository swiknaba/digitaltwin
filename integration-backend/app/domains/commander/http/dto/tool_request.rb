# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Http
      module Dto
        class ToolRequest < T::Struct
          const :name, String
          const :arguments, T::Hash[String, Object]
        end
      end
    end
  end
end
