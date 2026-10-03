# typed: strict
# frozen_string_literal: true

module Domains
  module Reviews
    module Errors
      # A stored review row does not match its typed shape.
      class MalformedRecord < ArgumentError; end
    end
  end
end
