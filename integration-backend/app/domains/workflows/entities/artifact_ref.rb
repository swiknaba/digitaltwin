# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Entities
      class ArtifactRef < T::Struct
        const :kind, String
        const :commit, String
        const :path, T.nilable(String)
      end
    end
  end
end
