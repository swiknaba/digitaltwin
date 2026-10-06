# frozen_string_literal: true

module SpecSupport
  module AgentsviewUsage
    class FixtureRunner
      include Adapters::Mcp::AgentsviewUsageRunnerInterface

      def initialize(&implementation)
        @implementation = implementation
      end

      def run(environment:, argv:)
        @implementation.call(environment, argv)
      end
    end
  end
end
