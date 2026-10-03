# typed: strict
# frozen_string_literal: true

module Domains
  module Messaging
    module Errors
      # A stored inbox row does not match its typed shape.
      class MalformedRecord < ArgumentError; end
    end
  end
end
