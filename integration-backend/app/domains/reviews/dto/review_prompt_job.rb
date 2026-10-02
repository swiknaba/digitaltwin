# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    module Dto
      # Payload of review.prompt jobs.
      class ReviewPromptJob < T::Struct
        include Kirei::Domain::ValueObject

        const :review_id, Integer
      end
    end
  end
end
