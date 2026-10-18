# typed: strict
# frozen_string_literal: true

module Adapters
  module FutureTasks
    # A verified caller context. Actor, Commander conversation, and authority are
    # derived from a short-lived capability, never accepted from a tool payload.
    class Capability < T::Struct
      include Kirei::Domain::ValueObject

      const :id, String
      const :actor_id, String
      const :conversation_id, String
      const :owner, T::Boolean
    end
  end
end
