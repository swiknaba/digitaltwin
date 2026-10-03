# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # Payload of workflow.provision jobs.
      class ProvisionJob < T::Struct
        include Kirei::Domain::ValueObject

        const :request_id, String
      end
    end
  end
end
