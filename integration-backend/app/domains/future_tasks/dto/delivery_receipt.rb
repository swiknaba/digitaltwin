# typed: strict
# frozen_string_literal: true

module Domains
  module FutureTasks
    module Dto
      class DeliveryReceipt < T::Struct
        include Kirei::Domain::ValueObject

        const :delivery_key, String
        const :commander_item_id, String
      end
    end
  end
end
