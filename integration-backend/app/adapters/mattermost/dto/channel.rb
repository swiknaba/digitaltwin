# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    module Dto
      class Channel < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
      end
    end
  end
end
