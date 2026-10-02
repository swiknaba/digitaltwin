# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Entities
      class Outcome < T::Struct
        const :status, String
        const :reason, String
        const :links, T::Array[String], default: []
      end
    end
  end
end
