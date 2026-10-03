# typed: strict
# frozen_string_literal: true

module FullStackFixture
  class Composition < Services::Composition
    extend T::Sig

    sig { returns(Adapters::Herdr::Client) }
    private def herdr
      ObservedHerdr.new
    end

    sig { returns(Domains::Workflows::Policy) }
    private def policy = DispatchPolicy.new
  end
end
