# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    module Dto
      # A handler's expected outcome; the worker applies the matching store transition.
      class Decision < T::Struct
        extend T::Sig
        include Kirei::Domain::ValueObject

        const :action, DecisionAction
        const :reason, T.nilable(String), default: nil

        sig { returns(Decision) }
        def self.complete = new(action: DecisionAction::Complete)

        sig { params(reason: String).returns(Decision) }
        def self.defer(reason) = new(action: DecisionAction::Defer, reason: reason)

        sig { params(reason: String).returns(Decision) }
        def self.block(reason) = new(action: DecisionAction::Block, reason: reason)
      end
    end
  end
end
