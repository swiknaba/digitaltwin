# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class VerifiedDelivery
      class Channel < T::Struct
        const :id, String
      end
    end
  end
end
