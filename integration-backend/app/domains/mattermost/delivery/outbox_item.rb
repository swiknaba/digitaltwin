# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class Delivery
      class OutboxItem < T::Struct
        const :id, String
        const :status, String
        const :bot, String
        const :channel_id, String
        const :thread_id, T.nilable(String)
        const :body, String
        const :response_key, String
        const :created_at, Time
      end
    end
  end
end
