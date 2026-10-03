# typed: strict
# frozen_string_literal: true

module Adapters
  module Git
    # Source-control hosting (forge) commands: private repository creation and clone.
    class Repositories
      extend T::Sig

      # Argument-injection guard only; Domains::Projects owns the full slug rule.
      SLUG = T.let(%r{\A[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9][A-Za-z0-9_.-]*\z}, Regexp)

      sig { params(slug: String, destination: String).void }
      def clone(slug:, destination:)
        _output, status = Open3.capture2e("git", "clone", "--", "https://github.com/#{slug!(slug)}.git", destination)
        ensure_success!(status)
      end

      sig { params(slug: String).void }
      def create_private(slug:)
        _output, status = Open3.capture2e("gh", "repo", "create", slug!(slug), "--private")
        ensure_success!(status)
      end

      sig { params(slug: String).returns(String) }
      private def slug!(slug)
        raise ArgumentError, "Expected owner/repository slug" unless slug.match?(SLUG)

        slug
      end

      sig { params(status: Process::Status).void }
      private def ensure_success!(status)
        raise Errors::OperationFailed, "GitHub operation failed; reconcile before retry" unless status.success?
      end
    end
  end
end
