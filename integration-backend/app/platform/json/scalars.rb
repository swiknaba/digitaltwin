# typed: strict
# frozen_string_literal: true

module Platform
  module Json
    Scalars = T.type_alias { T::Hash[String, T.any(String, Integer, T::Boolean, NilClass)] }
  end
end
