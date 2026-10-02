# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    module Dto
      class ChannelMember < T::Struct
        include Kirei::Domain::ValueObject

        const :channel_id, String
        const :user_id, String
      end
    end
  end
end
