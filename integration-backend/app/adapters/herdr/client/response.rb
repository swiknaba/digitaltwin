# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    class Client
      class Response < T::Struct
        const :id, String
        const :result_type, String
        const :payload, Client::JsonObject
      end
    end
  end
end
