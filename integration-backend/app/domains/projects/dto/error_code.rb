# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    module Dto
      # Expected failure codes of the projects context.
      class ErrorCode < T::Enum
        enums do
          MembershipRequired = new("membership_required")
          InvalidSlug = new("invalid_slug")
          ChannelEnrolledElsewhere = new("channel_enrolled_elsewhere")
          AlreadyEnrolled = new("already_enrolled")
          WorkspaceRejected = new("workspace_rejected")
        end
      end
    end
  end
end
