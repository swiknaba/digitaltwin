# typed: strict
# frozen_string_literal: true

module Services
  module Inbound
    module Dto
      # How RecordDelivery classified a delivery, with the reason text.
      class IngestOutcome < T::Struct
        include Kirei::Domain::ValueObject

        const :status, IngestStatus
        const :reason, String
      end
    end
  end
end
