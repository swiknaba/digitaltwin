# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class VerifiedDelivery
      class Post < T::Struct
        const :id, String
        const :channel_id, String
        const :user_id, String
        const :root_id, T.nilable(String)
        const :message, String
        const :create_at, Integer
        const :update_at, Integer
        const :delete_at, Integer
      end
    end
  end
end
