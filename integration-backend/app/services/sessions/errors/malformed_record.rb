# typed: strict
# frozen_string_literal: true

module Services
  module Sessions
    module Errors
      # A raw workflow or callback row does not have the expected shape.
      class MalformedRecord < StandardError; end
    end
  end
end
