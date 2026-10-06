# frozen_string_literal: true

module SpecSupport
  module AgentsviewUsage
    class FixtureAuthorizer
      include Adapters::Mcp::AgentsviewUsageAuthorizerInterface

      def initialize(&implementation)
        @implementation = implementation
      end

      def authorize(token:)
        @implementation.call(token)
      end
    end
  end
end
