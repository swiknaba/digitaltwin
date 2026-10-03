# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    module Dto
      # One review round of a workflow gate.
      class ReviewView < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :workflow_id, String
        const :gate, Workflows::Dto::Gate
        const :round, Integer
        const :target_commit, String
        const :base_commit, T.nilable(String)
        const :review_commit, T.nilable(String)
        const :review_path, String
        const :verdict, T.nilable(Verdict)
        const :reviewer_configuration, Workflows::Dto::RoleConfig
        const :dispatch_state, DispatchState
        const :created_at, Time
      end
    end
  end
end
