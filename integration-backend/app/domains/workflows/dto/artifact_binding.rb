# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # The commit and path a workflow recorded for one artifact gate. Approval
      # evidence checks read it, so all callers parse it here.
      class ArtifactBinding < T::Struct
        extend T::Sig
        include Kirei::Domain::ValueObject

        const :commit, T.nilable(String)
        const :path, T.nilable(String)

        # Sequel returns JSONB columns as a Delegator, which is not an Object.
        sig { params(artifacts: BasicObject, gate: String).returns(T.nilable(ArtifactBinding)) }
        def self.from_artifacts(artifacts:, gate:)
          refs = Sequel::Postgres::JSONBHash === artifacts ? artifacts.to_hash : Hash.try_convert(artifacts)
          ref = refs && Hash.try_convert(refs[gate])
          return nil unless ref

          commit = ref["commit"]
          path = ref["path"]
          new(commit: commit.is_a?(String) ? commit : nil, path: path.is_a?(String) ? path : nil)
        end
      end
    end
  end
end
