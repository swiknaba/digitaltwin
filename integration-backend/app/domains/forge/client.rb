# frozen_string_literal: true

require "open3"
module Domains
  module Forge
    class Client
      def clone(slug:, destination:)
        Domains::Projects::RepositoryIdentity.slug!(slug)
        run("git", "clone", "--", "https://github.com/#{slug}.git", destination)
      end

      def create_private(slug:)
        Domains::Projects::RepositoryIdentity.slug!(slug)
        run("gh", "repo", "create", slug, "--private")
      end
      private def run(*argv)
        _output, status = Open3.capture2e(*argv)
        raise "GitHub operation failed; reconcile before retry" unless status.success?
      end
    end
  end
end
