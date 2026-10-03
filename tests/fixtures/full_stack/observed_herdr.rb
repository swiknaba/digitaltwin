# typed: strict
# frozen_string_literal: true

module FullStackFixture
  # Observability only: execute the real adapter and preserve every failure.
  class ObservedHerdr < Adapters::Herdr::Client
    extend T::Sig

    sig { override.params(pane_id: String, name: String, launch: Adapters::Herdr::Dto::LaunchSpec).returns(Adapters::Herdr::Dto::Pane) }
    def start(pane_id:, name:, launch:)
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
