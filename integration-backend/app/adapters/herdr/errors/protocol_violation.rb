# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    module Errors
      # The socket response does not match the captured Herdr schema. It
      # subclasses IOError, so callers treat it as unproved runtime state.
      class ProtocolViolation < IOError
        extend T::Sig

        sig { returns(T.nilable(String)) }
        attr_reader :code

        sig { params(message: String, code: T.nilable(String)).void }
        def initialize(message, code: nil)
          @code = code
          super(message)
        end
      end
    end
  end
end
