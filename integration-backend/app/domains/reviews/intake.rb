# typed: strict
# frozen_string_literal: true

require "digest"

module Domains
  module Reviews
    # Validates the short-lived callback capability before durable queueing. Git
    # and Herdr evidence are intentionally checked by the worker that owns them.
    class Intake
      extend T::Sig

      CallbackPayload = T.type_alias { T::Hash[String, Object] }

      class Session < T::Struct
        const :id, String
        const :workflow_id, String
        const :generation, Integer
        const :credential_expires_at, Time
      end

      sig { params(db: Sequel::Database).void }
      def initialize(db)
        @db = db
      end

      sig do
        params(token: String, generation: Integer, action: String, commit: String, kind: T.nilable(String), verdict: T.nilable(String)).returns(String)
      end
      def enqueue(token:, generation:, action:, commit:, kind: nil, verdict: nil)
        role = callback_role(action)
        validate_callback!(action: action, generation: generation, commit: commit, kind: kind, verdict: verdict)

        session = active_session(token: token, generation: generation, role: role)
        payload = callback_payload(session_id: session.id, generation: generation, action: action, commit: commit, kind: kind, verdict: verdict)
        key = "review:callback:#{Digest::SHA256.hexdigest(JSON.generate(payload))}"
        Domains::Jobs::Store.new(@db).enqueue(kind: "review.callback", payload: payload, key: key)
        "queued"
      end

      private

      sig { params(action: String).returns(String) }
      def callback_role(action)
        raise ArgumentError, "Invalid callback" unless %w[artifact review].include?(action)

        action == "artifact" ? "writer" : "reviewer"
      end

      sig { params(action: String, generation: Integer, commit: String, kind: T.nilable(String), verdict: T.nilable(String)).void }
      def validate_callback!(action:, generation:, commit:, kind:, verdict:)
        raise ArgumentError, "Invalid callback" unless generation >= 0 && commit.match?(/\A[0-9a-f]{40}\z/)
        raise ArgumentError, "Invalid artifact" if action == "artifact" && !%w[spec plan implementation].include?(kind)
        raise ArgumentError, "Invalid verdict" if action == "review" && !%w[approve changes_requested].include?(verdict)
      end

      sig { params(token: String, generation: Integer, role: String).returns(Session) }
      def active_session(token:, generation:, role:)
        row = @db[:sessions][credential_digest: Digest::SHA256.hexdigest(token), generation: generation, role: role, active: true]
        session = session_from(row)
        latest = @db[:sessions].where(workflow_id: session.workflow_id, role: role).max(:generation)
        raise ArgumentError, "Invalid session" unless latest == generation && session.credential_expires_at > Time.now

        session
      end

      sig { params(session_id: String, generation: Integer, action: String, commit: String, kind: T.nilable(String), verdict: T.nilable(String)).returns(CallbackPayload) }
      def callback_payload(session_id:, generation:, action:, commit:, kind:, verdict:)
        payload = T.let({ "session_id" => session_id, "generation" => generation, "action" => action, "commit" => commit }, CallbackPayload)
        if action == "artifact"
          raise ArgumentError, "Invalid artifact" unless kind

          payload["kind"] = kind
        else
          raise ArgumentError, "Invalid verdict" unless verdict

          payload["verdict"] = verdict
        end
        payload
      end

      sig { params(row: Object).returns(Session) }
      def session_from(row)
        raise ArgumentError, "Invalid session" unless row.is_a?(Hash)

        Session.new(id: string!(row, :id), workflow_id: string!(row, :workflow_id), generation: integer!(row, :generation), credential_expires_at: time!(row, :credential_expires_at))
      end

      sig { params(row: T::Hash[Object, Object], key: Symbol).returns(String) }
      def string!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Invalid session" }
        raise ArgumentError, "Invalid session" unless value.is_a?(String)

        value
      end

      sig { params(row: T::Hash[Object, Object], key: Symbol).returns(Integer) }
      def integer!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Invalid session" }
        raise ArgumentError, "Invalid session" unless value.is_a?(Integer)

        value
      end

      sig { params(row: T::Hash[Object, Object], key: Symbol).returns(Time) }
      def time!(row, key)
        value = row.fetch(key) { raise ArgumentError, "Invalid session" }
        raise ArgumentError, "Invalid session" unless value.is_a?(Time)

        value
      end
    end
  end
end
