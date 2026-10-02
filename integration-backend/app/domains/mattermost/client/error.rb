# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class Client
      class Error < StandardError
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
