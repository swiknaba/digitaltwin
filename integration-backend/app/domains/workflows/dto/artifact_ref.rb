# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # The exact commit and repository path a workflow recorded for one gate.
      # The implementation gate has no path.
      class ArtifactRef < T::Struct
        extend T::Sig
        include Kirei::Domain::ValueObject

        const :commit, String
        const :path, T.nilable(String)

        # Keeps today's JSONB shape: "path" stays present as null, and the key
        # order matches what PostgreSQL returns for the stored object. `super`
        # keeps unknown stored keys, so Records can detect them.
        sig { params(strict: T::Boolean).returns(T::Hash[String, T.nilable(String)]) }
        def serialize(strict = true) = { "path" => path }.merge(super)
      end
    end
  end
end
