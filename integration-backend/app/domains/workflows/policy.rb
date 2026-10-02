# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    # Pure policy preparation, not a live review/session coordinator.
    class Policy
      extend T::Sig

      sig { params(writer: Entities::RoleConfig, reviewer: Entities::RoleConfig).returns(T::Boolean) }
      def diverse?(writer, reviewer)
        writer.provider != reviewer.provider && writer.family != reviewer.family
      end

      sig do
        params(
          actor: Domains::Messaging::Dto::VerifiedActor,
          channel_id: String,
          current_commit: String,
          reviewed_commit: String,
          verdict: String,
          requested_commit: String
        ).returns(T::Boolean)
      end
      def human_approval?(actor:, channel_id:, current_commit:, reviewed_commit:, verdict:, requested_commit:)
        actor.member && !actor.bot && actor.channel_id == channel_id && verdict == "approve" &&
          !current_commit.to_s.empty? && current_commit == reviewed_commit && current_commit == requested_commit
      end

      sig { params(state: String).returns(T::Boolean) }
      def settled?(state) = %w[idle done].include?(state)

      # Cannot be enabled by ENV: requires reviewed release-bound evidence/code.
      sig { returns(T::Boolean) }
      def dispatch_allowed? = false
    end
  end
end
