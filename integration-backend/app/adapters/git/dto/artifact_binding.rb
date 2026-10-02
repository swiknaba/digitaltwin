# typed: strict
# frozen_string_literal: true

module Adapters
  module Git
    module Dto
      # The commit and path a workflow recorded for one artifact gate.
      class ArtifactBinding < T::Struct
        include Kirei::Domain::ValueObject

        const :commit, T.nilable(String)
        const :path, T.nilable(String)
      end
    end
  end
end
