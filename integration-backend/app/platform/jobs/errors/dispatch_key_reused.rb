# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    module Errors
      # Subclasses ArgumentError so existing ArgumentError boundaries keep rejecting reuse.
      class DispatchKeyReused < ArgumentError; end
    end
  end
end
