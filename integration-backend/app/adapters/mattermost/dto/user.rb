# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    module Dto
      # Absent `is_bot` means false: v11.11.1 omits false in authenticated User JSON.
      class User < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :delete_at, Integer
        const :bot, T::Boolean
      end
    end
  end
end
