# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    module Errors
      # Transport failure: HTTP status, credential, size, or envelope. Callers
      # retry and keep checkpoints.
      class RequestFailed < StandardError
        extend T::Sig

        sig { returns(T.nilable(Integer)) }
        attr_reader :status

        sig { params(message: String, status: T.nilable(Integer)).void }
        def initialize(message, status: nil)
          @status = status
          super(message)
        end
      end
    end
  end
end
