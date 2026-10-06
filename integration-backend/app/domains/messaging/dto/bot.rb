# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # Bot account that posts an outbox message; values are persisted in outbox.bot.
      class Bot < T::Enum
        enums do
          Commander = new("commander")
          Agent = new("agent")
        end
      end
    end
  end
end
