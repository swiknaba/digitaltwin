# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Dto
      # Payload of session.followup jobs.
      class FollowupJob < T::Struct
        include Kirei::Domain::ValueObject

        const :followup_id, String
      end
    end
  end
end
