# typed: strict
# frozen_string_literal: true

module Adapters
  module Mcp
    module AgentsviewUsageAuthorizerInterface
      extend T::Helpers

      extend T::Sig

      interface!

      sig { abstract.params(token: String).void }
      def authorize(token:); end
    end
  end
end
