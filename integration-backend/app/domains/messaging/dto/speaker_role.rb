# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # Role label of an outbox message; values are persisted in outbox.role.
      class SpeakerRole < T::Enum
        enums do
          Controller = new("controller")
          Writer = new("writer")
          Reviewer = new("reviewer")
        end
      end
    end
  end
end
