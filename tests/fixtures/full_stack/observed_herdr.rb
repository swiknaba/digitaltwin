# typed: strict
# frozen_string_literal: true

module FullStackFixture
  # Observability only: execute the real adapter and preserve every failure.
  class ObservedHerdr < Adapters::Herdr::Client
    extend T::Sig

    # Test-only startup diagnostics retain a schema-shaped code but never the
    # server message. Production continues to expose only allowlisted codes.
    sig { override.params(line: String, correlation_id: String).returns(Adapters::Herdr::Client::Response) }
    private def response_from(line, correlation_id)
      parsed = JSON.parse(line)
      code = parsed.dig("error", "code") if parsed.is_a?(Hash)
      warn "Fixture Herdr raw rejection code: #{code}" if code.is_a?(String) && /\A[a-z0-9_]+\z/.match?(code)
      super
    end

    sig { override.params(pane_id: String, name: String, launch: Adapters::Herdr::Dto::LaunchSpec, workspace_id: T.nilable(String)).returns(Adapters::Herdr::Dto::Pane) }
    def start(pane_id:, name:, launch:, workspace_id: nil)
      super
    rescue Adapters::Herdr::Errors::ProtocolViolation => error
      warn "Fixture Herdr startup failed: #{error.message}"
      raise
    end

    sig { override.params(pane_id: String, text: String).void }
    def prompt(pane_id:, text:)
      super
    rescue Adapters::Herdr::Errors::ProtocolViolation => error
      warn "Fixture Herdr prompt failed: #{error.message}"
      raise
    end
  end
end
