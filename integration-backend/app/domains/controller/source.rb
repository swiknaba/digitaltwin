# frozen_string_literal: true

module Domains
  module Controller
    class Source
      def initialize(db, resolver:, membership:)
        @db, @resolver, @membership = db, resolver, membership
      end

      def human(id, destination: nil)
        row = @db[:inbox][id: id] or raise ArgumentError, "Missing verified source"
        d = @resolver.delivery(post_id: row[:post_id], channel_id: row[:channel_id], event_kind: "posted")
        raise ArgumentError, "Human source changed" unless d.actor.member && !d.actor.bot && d.actor.user_id == row[:user_id] && d.post_revision == row[:post_revision] && d.body == row[:verified_delivery].fetch("body")
        raise ArgumentError, "Destination membership required" if destination && !@membership.call(destination, d.actor.user_id)

        d
      end
    end
  end
end
