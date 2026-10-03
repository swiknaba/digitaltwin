# typed: strict
# frozen_string_literal: true

module Platform
  module Errors
    # Raised by Platform::Unwrap for a failed Result. It subclasses
    # ArgumentError so callers that are not migrated keep their existing
    # rescue and retry behavior for the former ArgumentError paths.
    class ResultFailed < ArgumentError; end
  end
end
