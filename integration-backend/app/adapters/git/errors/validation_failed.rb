# typed: strict
# frozen_string_literal: true

module Adapters
  module Git
    module Errors
      # A local git query failed. It subclasses ArgumentError, so workspace
      # callers keep rejecting the request as before.
      class ValidationFailed < ArgumentError; end
    end
  end
end
