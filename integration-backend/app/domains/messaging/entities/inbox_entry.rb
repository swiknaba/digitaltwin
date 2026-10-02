# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: inbox
#
#  id                  :integer             not null, primary key
#  channel_id          :text                not null
#  post_id             :text                not null
#  thread_id           :text                not null
#  user_id             :text                not null
#  event_kind          :text                not null
#  post_revision       :bigint              not null
#  verified_delivery   :jsonb               not null
#  created_at          :timestamp without time zone, not null
#

module Domains
  module Messaging
    module Entities
      class InboxEntry < T::Struct
        extend T::Sig
        include Kirei::Model
        include Kirei::Domain::Entity

        sig { override.returns(String) }
        def self.table_name = "inbox"

        const :id, Integer
        const :channel_id, String
        const :post_id, String
        const :thread_id, String
        const :user_id, String
        const :event_kind, Dto::EventKind
        const :post_revision, Integer
        const :verified_delivery, Dto::VerifiedDelivery
        const :created_at, Time
      end
    end
  end
end
