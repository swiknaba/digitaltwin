# typed: strict
# frozen_string_literal: true

module Adapters
  module Mcp
    module AgentsviewUsageRunnerInterface
      extend T::Helpers

      extend T::Sig

      interface!

      sig { abstract.params(environment: T::Hash[String, String], argv: T::Array[String]).returns(String) }
      def run(environment:, argv:); end
    end
  end
end
