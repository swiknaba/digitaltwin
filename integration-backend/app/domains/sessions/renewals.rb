# typed: strict
# frozen_string_literal: true

module Domains
  module Sessions
    # Credential renewal schedule. A renewal job runs 5 minutes before expiry;
    # its dispatch key includes the expiry, so each extension schedules once.
    class Renewals
      extend T::Sig

      sig { params(registry: Registry, jobs: Platform::Jobs::Store).void }
      def initialize(registry: Registry.new, jobs: Platform::Jobs::Store.new)
        @registry = registry
        @jobs = jobs
      end

      # Returns the renewal job id.
      sig { params(session: Dto::SessionView).returns(String) }
      def schedule(session:)
        expires_at = session.credential_expires_at
        @jobs.enqueue(kind: Platform::Jobs::Dto::JobKind::SessionRenew, payload: Dto::RenewalJob.new(session_id: session.id, generation: session.generation),
                      dispatch_key: "session:renew:#{session.id}:#{expires_at.to_i}", available_at: [Time.now, expires_at - 300].max)
      end

      sig { void }
      def schedule_active
        @registry.all_active.each { |session| schedule(session: session) }
      end

      # Records a verified renewal.
      sig { params(session_id: String, expires_at: Time).void }
      def extend_credential(session_id:, expires_at:)
        Entities::RuntimeSession.query.where(id: session_id).update(credential_expires_at: expires_at, last_verified_at: Time.now)
      end
    end
  end
end
