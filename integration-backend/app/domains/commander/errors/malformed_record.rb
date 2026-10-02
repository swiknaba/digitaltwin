# typed: strict
# frozen_string_literal: true

module Domains
  module Commander
    module Errors
      # A stored commander row does not match its typed shape.
      class MalformedRecord < ArgumentError; end
    end
  end
end
