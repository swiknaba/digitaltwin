# typed: strict
# frozen_string_literal: true

require "open3"
module Domains
  module Forge
    class Client
      extend T::Sig

      class OperationError < RuntimeError; end

      sig { params(slug: String, destination: String).void }
      def clone(slug:, destination:)
        Domains::Projects::RepositoryIdentity.slug!(slug)
        _output, status = Open3.capture2e("git", "clone", "--", "https://github.com/#{slug}.git", destination)
        ensure_success!(status)
      end

      sig { params(slug: String).void }
      def create_private(slug:)
        Domains::Projects::RepositoryIdentity.slug!(slug)
        _output, status = Open3.capture2e("gh", "repo", "create", slug, "--private")
        ensure_success!(status)
      end

      private

      sig { params(status: Process::Status).void }
      def ensure_success!(status)
        raise OperationError, "GitHub operation failed; reconcile before retry" unless status.success?
      end
    end
  end
end
