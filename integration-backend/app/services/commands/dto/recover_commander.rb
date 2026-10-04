# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # `@<agent> recover-commander <request_id>`.
      class RecoverCommander < T::Struct
        include Kirei::Domain::ValueObject

        const :request_id, String
      end
    end
  end
end
