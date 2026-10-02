# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Dto
      # Mattermost post event kind; values are persisted in inbox.event_kind.
      class EventKind < T::Enum
        enums do
          Posted = new("posted")
          PostEdited = new("post_edited")
          PostDeleted = new("post_deleted")
        end
      end
    end
  end
end
