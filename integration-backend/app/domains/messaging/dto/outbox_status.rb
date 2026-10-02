# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # Delivery state of an outbox row; values match the outbox_status constraint.
      class OutboxStatus < T::Enum
        enums do
          Pending = new("pending")
          Delivered = new("delivered")
          Uncertain = new("uncertain")
          Blocked = new("blocked")
        end
      end
    end
  end
end
