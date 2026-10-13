# typed: strict
# frozen_string_literal: true

module Domains
  module FutureTasks
    module Dto
      # Durable outbox payload. The delivery key and outcome form its idempotency key.
      class OutcomeJob < T::Struct
        include Kirei::Domain::ValueObject

        const :delivery_key, String
        const :outcome, String
      end
    end
  end
end
