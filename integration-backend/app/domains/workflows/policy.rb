# frozen_string_literal: true

module Domains
  module Workflows
    # Pure policy preparation, not a live review/session coordinator.
    class Policy
      def diverse?(writer, reviewer)
        writer.provider != reviewer.provider && writer.family != reviewer.family
      end

      def human_approval?(actor:, channel_id:, current_commit:, reviewed_commit:, verdict:, requested_commit:)
        actor.member && !actor.bot && actor.channel_id == channel_id && verdict == "approve" &&
          !current_commit.to_s.empty? && current_commit == reviewed_commit && current_commit == requested_commit
      end

      def settled?(state) = %w[idle done].include?(state)
      # Cannot be enabled by ENV: requires reviewed release-bound evidence/code.
      def dispatch_allowed? = false
    end
  end
end
