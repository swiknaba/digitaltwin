# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    module Dto
      # Payload of review.callback jobs; prop order fixes the dispatch-key digest.
      class CallbackJob < T::Struct
        include Kirei::Domain::ValueObject

        const :session_id, String
        const :generation, Integer
        const :action, String
        const :commit, String
        const :kind, T.nilable(String), default: nil
        const :verdict, T.nilable(String), default: nil
      end
    end
  end
end
