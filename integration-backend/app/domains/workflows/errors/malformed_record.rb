# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Errors
      # A stored workflows-context row or JSONB value does not match its type.
      # It subclasses ArgumentError, so callers keep today's rejection path.
      class MalformedRecord < ArgumentError; end
    end
  end
end
