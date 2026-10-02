# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Dto
      # Payload of session.start and session.stop jobs.
      class SessionOperationJob < T::Struct
        include Kirei::Domain::ValueObject

        const :operation_id, String
      end
    end
  end
end
