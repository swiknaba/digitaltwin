# typed: strict
# frozen_string_literal: true

module Services
  module Commander
    module Dto
      # A routed follow-up, or nil when routing asked the human to clarify.
      class RouteOutcome < T::Struct
        include Kirei::Domain::ValueObject

        const :followup, T.nilable(Domains::Commander::Dto::FollowupView)
      end
    end
  end
end
