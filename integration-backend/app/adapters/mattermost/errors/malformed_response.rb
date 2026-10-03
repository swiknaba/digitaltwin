# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    module Errors
      # A field has the wrong JSON type. It subclasses ArgumentError, so
      # verification callers reject or quarantine it as before.
      class MalformedResponse < ArgumentError; end
    end
  end
end
