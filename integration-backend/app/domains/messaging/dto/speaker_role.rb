# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # Role label of an outbox message; values are persisted in outbox.role.
      class SpeakerRole < T::Enum
        enums do
          Commander = new("commander")
          Writer = new("writer")
          Reviewer = new("reviewer")
        end
      end
    end
  end
end
