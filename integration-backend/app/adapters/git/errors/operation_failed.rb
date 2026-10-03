# typed: strict
# frozen_string_literal: true

module Adapters
  module Git
    module Errors
      # A forge operation failed after it may have started; reconcile before retry.
      class OperationFailed < RuntimeError; end
    end
  end
end
