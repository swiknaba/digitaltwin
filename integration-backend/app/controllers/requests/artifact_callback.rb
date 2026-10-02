# typed: strict
# frozen_string_literal: true

module Controllers
  module Requests
    class ArtifactCallback < T::Struct
      const :token, String
      const :generation, Integer
      const :kind, String
      const :commit, String
    end
  end
end
