# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class VerifiedDelivery
      class User < T::Struct
        const :id, String
        const :delete_at, Integer
        const :bot, T::Boolean
      end
    end
  end
end
