# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    module Dto
      # A Worker chat message queued in its bound workflow thread.
      class QueuedChat < T::Struct
        include Kirei::Domain::ValueObject

        const :outbox_id, String
      end
    end
  end
end
