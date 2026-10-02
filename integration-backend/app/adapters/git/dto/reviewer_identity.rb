# typed: strict
# frozen_string_literal: true

module Adapters
  module Git
    module Dto
      # Reviewer metadata that a review file must record.
      class ReviewerIdentity < T::Struct
        include Kirei::Domain::ValueObject

        const :provider, String
        const :model, String
        const :family, String
      end
    end
  end
end
