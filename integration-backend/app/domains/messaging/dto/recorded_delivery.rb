# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # Result of recording a delivery. A duplicate has no new inbox id.
      class RecordedDelivery < T::Struct
        include Kirei::Domain::ValueObject

        const :inbox_id, T.nilable(Integer)
        const :duplicate, T::Boolean
      end
    end
  end
end
