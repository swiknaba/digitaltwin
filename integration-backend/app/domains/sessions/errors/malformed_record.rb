# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    module Errors
      # A stored session JSONB value does not match its typed shape.
      class MalformedRecord < ArgumentError; end
    end
  end
end
