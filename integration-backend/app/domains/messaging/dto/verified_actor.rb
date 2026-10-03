# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # Sender identity proven through authenticated REST.
      class VerifiedActor < T::Struct
        include Kirei::Domain::ValueObject

        const :user_id, String
        const :channel_id, String
        const :member, T::Boolean
        const :bot, T::Boolean
      end
    end
  end
end
