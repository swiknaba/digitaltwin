# frozen_string_literal: true

require "digest"
module Domains
  module Reviews
    # HTTP validates the callback capability, then leaves Git/Herdr checks on
    # the worker that owns the socket and repository mounts.
    class Intake
      def initialize(db) = @db = db

      def enqueue(token:, generation:, action:, commit:, kind: nil, verdict: nil)
        role = action == "artifact" ? "writer" : "reviewer"
        raise ArgumentError, "Invalid callback" unless %w[artifact review].include?(action) && generation.is_a?(Integer) && commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/)
        raise ArgumentError, "Invalid artifact" if action == "artifact" && !%w[spec plan implementation].include?(kind)
        raise ArgumentError, "Invalid verdict" if action == "review" && !%w[approve changes_requested].include?(verdict)

        s = @db[:sessions][credential_digest: Digest::SHA256.hexdigest(token), generation: generation, role: role, active: true]
        latest = s && @db[:sessions].where(workflow_id: s[:workflow_id], role: role).max(:generation)
        raise ArgumentError, "Invalid session" unless s && s[:credential_expires_at] > Time.now && latest == generation

        payload = { "session_id" => s[:id], "generation" => generation, "action" => action, "commit" => commit }
        payload[action == "artifact" ? "kind" : "verdict"] = action == "artifact" ? kind : verdict
        key = "review:callback:#{Digest::SHA256.hexdigest(JSON.generate(payload))}"
        Domains::Jobs::Store.new(@db).enqueue(kind: "review.callback", payload: payload, key: key)
        "queued"
      end
    end
  end
end
