# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    module Dto
      # Delivery state of a round's reviewer prompt. Sending and uncertain
      # prompts may have reached the reviewer and are never resent.
      class DispatchState < T::Enum
        extend T::Sig

        enums do
          Queued = new("queued")
          Sending = new("sending")
          Delivered = new("delivered")
          Uncertain = new("uncertain")
        end

        sig { returns(T::Boolean) }
        def unsettled?
          case self
          when Sending, Uncertain then true
          when Queued, Delivered then false
          else T.absurd(self)
          end
        end
      end
    end
  end
end
