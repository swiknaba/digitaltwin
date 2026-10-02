# typed: strict
# frozen_string_literal: true

module Services
  module Workflows
    module Dto
      # The review fields that workflow gates check. Task 8 replaces it with
      # the reviews context DTO.
      class ReviewRecord < T::Struct
        include Kirei::Domain::ValueObject

        const :id, Integer
        const :gate, String
        const :round, Integer
        const :target_commit, String
        const :review_commit, T.nilable(String)
        const :review_path, String
        const :verdict, T.nilable(String)
      end
    end
  end
end
