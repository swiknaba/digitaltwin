# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    # Pure policy preparation, not a live review/session coordinator.
    class Policy
      extend T::Sig

      sig { params(local_dispatch_activation: T.nilable(Dto::LocalDispatchActivation)).void }
      def initialize(local_dispatch_activation: nil)
        @local_dispatch_activation = local_dispatch_activation
      end

      sig { params(writer: Dto::RoleConfig, reviewer: Dto::RoleConfig).returns(T::Boolean) }
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

      # Local dispatch requires the checked, read-only operator acknowledgement
      # file. Hosted activation remains intentionally outside this repository.
      sig { returns(T::Boolean) }
      def dispatch_allowed? = !@local_dispatch_activation.nil?
    end
  end
end
