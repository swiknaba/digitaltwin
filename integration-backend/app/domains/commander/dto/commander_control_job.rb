# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # Payload of commander.control jobs.
      class CommanderControlJob < T::Struct
        include Kirei::Domain::ValueObject

        const :inbox_id, String
        const :workflow_id, String
        const :action, String
        const :expected_version, Integer
      end
    end
  end
end
