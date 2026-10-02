# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    # Temporary bridge for handler maps built from procs; Task 10 removes it.
    class CallableHandler
      extend T::Sig
      include Handler

      Callable = T.type_alias { T.proc.params(job: Dto::ClaimedJob).returns(Dto::Decision) }

      sig { params(callable: Callable).void }
      def initialize(callable)
        @callable = callable
      end

      sig { override.params(job: Dto::ClaimedJob).returns(Dto::Decision) }
      def call(job:) = @callable.call(job)
    end
  end
end
