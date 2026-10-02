# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # A chat message to queue. The key makes the enqueue idempotent.
      class OutgoingMessage < T::Struct
        include Kirei::Domain::ValueObject

        const :channel_id, String
        const :thread_id, T.nilable(String)
        const :bot, Bot
        const :role, SpeakerRole
        const :body, String
        const :key, String
      end
    end
  end
end
