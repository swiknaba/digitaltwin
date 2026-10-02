# frozen_string_literal: true

require "digest"
module Domains
  module Controller
    class Requests
      def initialize(db, source:) = (@db, @source = db, source)

      def authorize(id, token, states: ["active"])
        r = @db[:master_requests][id: id, credential_digest: Digest::SHA256.hexdigest(token), state: states]
        s = r && @db[:sessions][id: r[:session_id], role: "controller", active: true]
        latest = @db[:sessions].where(role: "controller").max(:generation)
        raise ArgumentError, "Request capability expired or inactive" unless r && r[:expires_at] > Time.now && s && s[:credential_expires_at] > Time.now && s[:generation] == latest

        @source.human(r[:inbox_id])
        r
      end
    end
  end
end
