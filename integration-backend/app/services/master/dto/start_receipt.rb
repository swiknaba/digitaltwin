# typed: strict
# frozen_string_literal: true

module Services
  module Master
    module Dto
      # start_workflow: the queued workflow request.
      class StartReceipt < T::Struct
        include Kirei::Domain::ValueObject

        const :request_id, String
      end
    end
  end
end
