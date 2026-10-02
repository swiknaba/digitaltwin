# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    class Herdr
      class Response < T::Struct
        const :id, String
        const :result_type, String
        const :payload, Herdr::JsonObject
      end
    end
  end
end
