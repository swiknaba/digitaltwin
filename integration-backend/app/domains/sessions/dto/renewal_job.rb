# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # Payload of session.renew jobs.
      class RenewalJob < T::Struct
        include Kirei::Domain::ValueObject

        const :session_id, String
        const :generation, Integer
      end
    end
  end
end
