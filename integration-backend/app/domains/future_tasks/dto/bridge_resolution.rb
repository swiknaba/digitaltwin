# typed: strict
# frozen_string_literal: true

module Domains
  module FutureTasks
    module Dto
      # The bridge's authoritative answer for an existing delivery key. It never
      # authorizes a new key or a new Commander conversation.
      class BridgeResolution < T::Struct
        include Kirei::Domain::ValueObject

        const :receipt, T.nilable(DeliveryReceipt), default: nil
        const :terminal_failure, T.nilable(String), default: nil
      end
    end
  end
end
