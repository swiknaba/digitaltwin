# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    # Translates Herdr conversation evidence into the sessions domain's
    # RuntimeIdentity, and compares stored and live identities.
    class ConversationIdentity
      extend T::Sig

      Identity = Domains::Sessions::Dto::RuntimeIdentity
      Live = Dto::AgentSession

      # Herdr reported every identity field.
      sig { params(live: Live).returns(T::Boolean) }
      def self.proven?(live)
        [live.source, live.agent, live.kind, live.value].none?(&:empty?)
      end

      sig { params(live: Live).returns(Identity) }
      def self.from_live(live) = Identity.new(source: live.source, agent: live.agent, kind: live.kind, value: live.value)

      # A session without a stored identity never matches.
      sig { params(stored: T.nilable(Identity), live: T.nilable(Live)).returns(T::Boolean) }
      def self.same?(stored, live)
        return false unless stored

        live&.serialize == stored.serialize
      end
    end
  end
end
