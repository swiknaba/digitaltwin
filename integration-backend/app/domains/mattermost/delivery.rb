# frozen_string_literal: true

module Domains
  module Mattermost
    class Delivery
      def self.from_env(db)
        url = ENV.fetch("MATTERMOST_URL")
        clients, ids = {}, {}
        %w[worker agent].each do |role|
          clients[role] = Client.new(url: url, token_file: ENV.fetch("MATTERMOST_#{role.upcase}_TOKEN_FILE"))
          ids[role] = ENV.fetch("MATTERMOST_#{role.upcase}_BOT_ID")
        end
        new(db, clients: clients, bot_ids: ids)
      end

      def initialize(db, clients:, bot_ids:)
        @db, @clients, @bot_ids = db, clients, bot_ids
      end

      def call(job, jobs)
        row = @db[:outbox][id: job[:payload].fetch("outbox_id")]
        raise ArgumentError, "Unknown outbox item" unless row
        return if row[:status] == "delivered"
        raise "Outbox requires reconciliation" unless row[:status] == "pending"

        client = @clients.fetch(row[:bot])
        expected_bot = @bot_ids.fetch(row[:bot])
        verify_destination!(client, row, expected_bot)
        @db.transaction do
          raise "Lost external effect lease" unless jobs.begin_effect(id: job[:id], lease_token: job[:lease_token])

          @db[:outbox].where(id: row[:id]).update(status: "uncertain")
        end
        # Everything from here can have an unknown result. No blind resend.
        remote = client.post("/api/v4/posts",
                             { "channel_id" => row[:channel_id], "root_id" => row[:thread_id] || "", "message" => row[:body],
                               "props" => { "digitaltwin_response_key" => row[:response_key] } })
        verify_result!(remote, row, expected_bot)
        @db[:outbox].where(id: row[:id]).update(status: "delivered", remote_post_id: remote.fetch("id"))
      end

      def reconcile(outbox_id:)
        row = @db[:outbox][id: outbox_id]
        raise ArgumentError, "Expected uncertain delivery" unless row && row[:status] == "uncertain"

        client = @clients.fetch(row[:bot])
        expected_bot = @bot_ids.fetch(row[:bot])
        verify_destination!(client, row, expected_bot)
        since = [(row[:created_at].to_time.to_f * 1000).to_i - 1000, 1].max
        list = client.get("/api/v4/channels/#{row[:channel_id]}/posts?since=#{since}&collapsedThreads=false")
        matches = list.fetch("posts").values.select { |post|
          post.fetch("props", {})["digitaltwin_response_key"] == row[:response_key]
        }
        return false unless matches.size == 1

        verify_result!(matches.first, row, expected_bot)
        @db.transaction do
          @db[:outbox].where(id: row[:id], status: "uncertain").update(status: "delivered",
                                                                       remote_post_id: matches.first.fetch("id"))
          @db[:jobs].where(dispatch_key: "outbox:#{row[:id]}", status: "uncertain").update(status: "complete",
                                                                                           lease_token: nil, lease_expires_at: nil)
        end
        true
      end
      private def verify_destination!(client, row, expected_bot)
        [row[:channel_id], expected_bot, row[:thread_id]].compact.each do |id|
          raise ArgumentError, "Invalid Mattermost destination ID" unless id.match?(/\A[a-z0-9]{26}\z/)
        end
        me = client.get("/api/v4/users/me")
        raise ArgumentError, "Wrong bot identity" unless me["id"] == expected_bot && me["is_bot"] == true

        channel = client.get("/api/v4/channels/#{row[:channel_id]}")
        member = client.get("/api/v4/channels/#{row[:channel_id]}/members/#{expected_bot}")
        raise ArgumentError,
              "Bot/channel membership mismatch" unless channel["id"] == row[:channel_id] && member["channel_id"] == row[:channel_id] && member["user_id"] == expected_bot

        if row[:thread_id]
          root = client.get("/api/v4/posts/#{row[:thread_id]}")
          raise ArgumentError,
                "Invalid source thread" unless root["id"] == row[:thread_id] && root["channel_id"] == row[:channel_id] && root["root_id"].to_s.empty? && root["delete_at"] == 0
        end
      end
      private def verify_result!(post, row, bot_id)
        raise "Unverified Mattermost delivery result" unless post["id"].is_a?(String) && post["id"].match?(/\A[a-z0-9]{26}\z/) && post["channel_id"] == row[:channel_id] && post["root_id"].to_s == row[:thread_id].to_s && post["user_id"] == bot_id && post["message"] == row[:body]
      end
    end
  end
end
