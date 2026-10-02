# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # Delivery state of a follow-up. Sending and uncertain follow-ups may
      # have reached the Writer and are never resent.
      class FollowupStatus < T::Enum
        enums do
          Queued = new("queued")
          Sending = new("sending")
          Delivered = new("delivered")
          Uncertain = new("uncertain")
          Blocked = new("blocked")
        end
      end
    end
  end
end
