# typed: strict
# frozen_string_literal: true

module Platform
  class Lock
    # Subclasses ArgumentError so existing ArgumentError boundaries keep their responses.
    class Busy < ArgumentError; end
  end
end
