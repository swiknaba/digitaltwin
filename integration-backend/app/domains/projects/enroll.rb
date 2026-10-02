# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    class Enroll
      extend T::Sig

      sig do
        params(
          db: Sequel::Database,
          workspace: Workspace,
          forge: Domains::Forge::Client
        ).void
      end
      def initialize(db, workspace:, forge: Domains::Forge::Client.new)
        @db = db
        @workspace = workspace
        @forge = forge
      end

      sig do
        params(
          actor: Domains::Workflows::Entities::Actor,
          channel_id: String,
          slug: String,
          choice: String
        ).returns(Domains::Workflows::Entities::Outcome)
      end
      def call(actor:, channel_id:, slug:, choice:)
        return outcome("rejected",
                       "Verified human channel membership required") unless actor.member && !actor.bot && actor.channel_id == channel_id

        RepositoryIdentity.slug!(slug)
        raise ArgumentError, "Select clone/create_private/stop" unless %w[clone create_private stop].include?(choice)

        existing = @db[:projects][channel_id: channel_id]
        if existing
          return outcome("rejected", "Channel already enrolled to another repository") unless existing[:slug] == slug

          @workspace.resolve(slug: slug)
          return outcome("accepted", "Channel mapping retained")
        end
        path = @workspace.destination(slug: slug)
        unless File.exist?(path)
          return outcome("blocked", "Choose clone/create_private/stop") if choice == "stop"

          # Network work happens before short DB registration, never under a lock.
          @forge.create_private(slug: slug) if choice == "create_private"
          FileUtils.mkdir_p(File.dirname(path))
          @forge.clone(slug: slug, destination: path)
        end
        verified = @workspace.resolve(slug: slug)
        @db[:projects].insert(id: SecureRandom.uuid, channel_id: channel_id, slug: slug,
                              remote_identity: "github.com/#{slug.downcase}", workspace: verified)
        outcome("accepted", "Repository enrolled")
      rescue ArgumentError, Sequel::UniqueConstraintViolation => e
        outcome("rejected", e.is_a?(ArgumentError) ? e.message : "Repository/channel already enrolled")
      end

      private

      sig { params(status: String, reason: String).returns(Domains::Workflows::Entities::Outcome) }
      def outcome(status, reason)
        Domains::Workflows::Entities::Outcome.new(status: status, reason: reason)
      end
    end
  end
end
