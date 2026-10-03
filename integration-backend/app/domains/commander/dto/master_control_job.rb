# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # Payload of master.control jobs.
      class MasterControlJob < T::Struct
        include Kirei::Domain::ValueObject

        const :inbox_id, String
        const :workflow_id, String
        const :action, String
        const :expected_version, Integer
      end
    end
  end
end
