# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    module Dto
      # Payload of review.release jobs.
      class ReviewReleaseJob < T::Struct
        include Kirei::Domain::ValueObject

        const :workflow_id, String
      end
    end
  end
end
