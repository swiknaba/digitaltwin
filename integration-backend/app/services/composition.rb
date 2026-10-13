# typed: strict
# frozen_string_literal: true

module Services
  # Small composition root for Kirei's single retained bounded context.
  class Composition
    extend T::Sig

    @instance = T.let(nil, T.nilable(Composition))

    sig { returns(Composition) }
    def self.instance
      @instance ||= new(configuration: Configuration.from_env)
    end

    sig { returns(Configuration) }
    attr_reader :configuration

    sig { params(configuration: Configuration, future_tasks: T.nilable(Domains::FutureTasks::Tasks), gateway: T.nilable(Adapters::CommanderBridge::Gateway)).void }
    def initialize(configuration:, future_tasks: nil, gateway: nil)
      @configuration = configuration
      @future_tasks = T.let(future_tasks, T.nilable(Domains::FutureTasks::Tasks))
      @gateway = T.let(gateway, T.nilable(Adapters::CommanderBridge::Gateway))
    end

    sig { returns(Domains::FutureTasks::Tasks) }
    def future_tasks
      @future_tasks ||= Domains::FutureTasks::Tasks.new
    end

    sig { returns(Adapters::CommanderBridge::Gateway) }
    def commander_gateway
      @gateway ||= Adapters::CommanderBridge::UnavailableGateway.new
    end
  end
end
