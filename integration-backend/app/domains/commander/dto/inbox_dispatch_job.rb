# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # Payload of every router-produced inbox job kind.
      class InboxDispatchJob < T::Struct
        include Kirei::Domain::ValueObject

        const :inbox_id, String
        const :channel_id, String
        const :thread_id, String
        const :workflow_id, T.nilable(String), default: nil
        const :expected_version, T.nilable(Integer), default: nil
      end
    end
  end
end
