# typed: strict
# frozen_string_literal: true

module FullStackFixture
  # Loaded only by the disposable worker entrypoint; production policy stays closed.
  class DispatchPolicy < Domains::Workflows::Policy
    extend T::Sig

    sig { returns(T::Boolean) }
    def dispatch_allowed? = true
  end
end
