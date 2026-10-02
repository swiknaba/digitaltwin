# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    class RepositoryIdentity
      extend T::Sig

      SLUG_PATTERN = T.let(%r{\A[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9][A-Za-z0-9_.-]*\z}, Regexp)

      sig { params(slug: String).returns(T::Boolean) }
      def self.slug?(slug)
        slug.match?(SLUG_PATTERN) && !slug.end_with?(".git", ".")
      end

      sig { params(slug: String).returns(String) }
      def self.slug!(slug)
        raise ArgumentError, "Expected owner/repository slug" unless slug?(slug)

        slug
      end

      sig { params(remote: String, slug: String).returns(String) }
      def self.remote!(remote, slug)
        slug!(slug)
        patterns = [
          %r{\Ahttps://github\.com/([^/]+/[^/]+?)(?:\.git)?\z},
          %r{\Agit@github\.com:([^/]+/[^/]+?)(?:\.git)?\z},
          %r{\Assh://git@github\.com/([^/]+/[^/]+?)(?:\.git)?\z}
        ]
        actual = patterns.filter_map { |pattern| remote.match(pattern)&.[](1) }.first
        raise ArgumentError, "Git remote identity mismatch" unless actual&.downcase == slug.downcase

        "github.com/#{slug.downcase}"
      end
    end
  end
end
