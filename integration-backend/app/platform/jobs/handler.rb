# typed: strict
# frozen_string_literal: true

module Platform
  module Jobs
    # A job handler returns its expected outcome. Raised exceptions go to the
    # worker's retry path.
    module Handler
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(job: Dto::ClaimedJob).returns(Dto::Decision) }
      def call(job:); end
    end
  end
end
