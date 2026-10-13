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
      @gateway ||= configured_gateway
    end

    sig { returns(FutureTasks::CapabilityApi) }
    def future_task_api
      secret_file = @configuration.capability_secret_file
      raise "Future-task capability verifier is not configured" unless secret_file

      secret = File.read(secret_file).strip
      raise "Future-task capability secret file is empty" if secret.empty?

      FutureTasks::CapabilityApi.new(tasks: future_tasks, verifier: Adapters::FutureTasks::CapabilityVerifier.new(secret:), outcome_gateway: configured_outcome_gateway)
    end

    sig { returns(Adapters::FutureTasks::McpTool) }
    def mcp_future_tasks
      Adapters::FutureTasks::McpTool.new(api: future_task_api)
    end

    sig { returns(Adapters::FutureTasks::OpencodeTool) }
    def opencode_future_tasks
      Adapters::FutureTasks::OpencodeTool.new(api: future_task_api)
    end

    sig { returns(Adapters::CommanderBridge::Gateway) }
    private def configured_gateway
      url = @configuration.commander_bridge_url
      identity_file = @configuration.commander_bridge_identity_file
      return Adapters::CommanderBridge::UnavailableGateway.new unless url && identity_file

      identity = File.read(identity_file).strip
      raise "Commander bridge identity file is empty" if identity.empty?

      Adapters::CommanderBridge::ConfiguredGateway.new(base_url: url, identity: identity)
    end

    sig { returns(T.nilable(Adapters::CommanderBridge::Gateway)) }
    private def configured_outcome_gateway
      return nil unless @configuration.commander_bridge_url && @configuration.commander_bridge_identity_file

      commander_gateway
    end
  end
end
