# typed: strict
# frozen_string_literal: true

module Services
  class JobHandlers
    extend T::Sig

    Kind = Platform::Jobs::Dto::JobKind
    HandlerMap = T.type_alias { T::Hash[Platform::Jobs::Dto::JobKind, Platform::Jobs::Handler] }

    sig { params(composition: Composition).void }
    def initialize(composition:)
      @composition = composition
    end

    sig { returns(HandlerMap) }
    def call
      {
        Kind::FutureTaskDue => FutureTasks::DeliverDue.new(tasks: @composition.future_tasks, gateway: @composition.commander_gateway),
        Kind::FutureTaskReconcile => FutureTasks::ReconcileDue.new(tasks: @composition.future_tasks, gateway: @composition.commander_gateway),
        Kind::FutureTaskOutcome => FutureTasks::PublishOutcome.new(gateway: @composition.commander_gateway)
      }
    end
  end
end
