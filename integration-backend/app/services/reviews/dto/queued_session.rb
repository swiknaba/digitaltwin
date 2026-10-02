# typed: strict
# frozen_string_literal: true

module Services
  module Reviews
    module Dto
      # A callback caller already authenticated by QueueCallback.
      class QueuedSession < T::Struct
        include Kirei::Domain::ValueObject

        const :session_id, String
      end
    end
  end
end
