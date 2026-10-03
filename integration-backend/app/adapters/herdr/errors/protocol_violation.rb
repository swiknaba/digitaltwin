# typed: strict
# frozen_string_literal: true

module Adapters
  module Herdr
    module Errors
      # The socket response does not match the captured Herdr schema. It
      # subclasses IOError, so callers treat it as unproved runtime state.
      class ProtocolViolation < IOError; end
    end
  end
end
