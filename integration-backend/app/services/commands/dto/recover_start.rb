# typed: strict
# frozen_string_literal: true

module Services
  module Commands
    module Dto
      # `@<agent> recover-start <request_id> <thread_id>`.
      class RecoverStart < T::Struct
        include Kirei::Domain::ValueObject

        const :request_id, String
        const :thread_id, String
      end
    end
  end
end
