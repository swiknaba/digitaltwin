# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # Payload of mattermost.post jobs.
      class OutboxPostJob < T::Struct
        include Kirei::Domain::ValueObject

        const :outbox_id, String
      end
    end
  end
end
