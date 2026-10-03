# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    class Client
      class HttpResponse < T::Struct
        const :status, Integer
        const :body, String
      end
    end
  end
end
