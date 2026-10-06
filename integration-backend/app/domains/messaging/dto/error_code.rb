# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # Expected failure codes of the messaging context.
      class ErrorCode < T::Enum
        enums do
          MissingSource = new("missing_source")
          SourceChanged = new("source_changed")
          DestinationMembershipRequired = new("destination_membership_required")
          KeyReused = new("key_reused")
          AgentMessageRequiresThreadAndRole = new("agent_message_requires_thread_and_role")
        end
      end
    end
  end
end
