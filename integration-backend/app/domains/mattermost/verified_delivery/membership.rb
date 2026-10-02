# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class VerifiedDelivery
      class Membership < T::Struct
        const :channel_id, String
        const :user_id, String
      end
    end
  end
end
