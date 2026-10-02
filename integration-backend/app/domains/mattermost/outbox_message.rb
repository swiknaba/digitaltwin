# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: outbox
#
#  id                  :text                not null, primary key
#  response_key        :text                not null
#  channel_id          :text                not null
#  thread_id           :text                null
#  bot                 :text                not null
#  role                :text                null
#  body                :text                not null
#  status              :text                not null
#  remote_post_id      :text                null
#  created_at          :timestamp without time zone, not null
#

module Domains
  module Mattermost
    class OutboxMessage < T::Struct
      extend T::Sig
      include Kirei::Model

      sig { override.returns(String) }
      def self.table_name = "outbox"

      const :id, String
      const :response_key, String
      const :channel_id, String
      const :thread_id, T.nilable(String)
      const :bot, String
      const :role, String
      const :body, String
      const :status, String, default: "pending"
      const :remote_post_id, T.nilable(String), default: nil
      const :created_at, Time, factory: -> { Time.now.utc }
    end
  end
end
