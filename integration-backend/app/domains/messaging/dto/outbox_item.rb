# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # A persisted outbox message and its delivery state.
      class OutboxItem < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :response_key, String
        const :channel_id, String
        const :thread_id, T.nilable(String)
        const :bot, Bot
        const :role, T.nilable(SpeakerRole)
        const :body, String
        const :status, OutboxStatus
        const :remote_post_id, T.nilable(String)
        const :created_at, Time
      end
    end
  end
end
