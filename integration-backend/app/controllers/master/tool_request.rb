# typed: strict
# frozen_string_literal: true

module Controllers
  class Master
    class ToolRequest < T::Struct
      const :name, String
      const :arguments, T::Hash[String, Object]
    end
  end
end
