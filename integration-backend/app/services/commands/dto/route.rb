# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # `@<agent> route <workflow_id>` on the first line, followed by the instruction text.
      class Route < T::Struct
        include Kirei::Domain::ValueObject

        const :workflow_id, String
        const :text, String
      end
    end
  end
end
