# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # Payload of master.dispatch jobs.
      class MasterDispatchJob < T::Struct
        include Kirei::Domain::ValueObject

        const :request_id, String
      end
    end
  end
end
