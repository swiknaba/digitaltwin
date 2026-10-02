# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: audit
#
#  id                  :integer             not null, primary key
#  event_key           :text                not null
#  action              :text                not null
#  user_id             :text                null
#  channel_id          :text                null
#  post_id             :text                null
#  details             :jsonb               not null
#  created_at          :timestamp without time zone, not null
#

module Platform
  module Audit
    module Entities
      class Entry < T::Struct
        extend T::Sig
        include Kirei::Model
        include Kirei::Domain::Entity

        sig { override.returns(String) }
        def self.table_name = "audit"

        const :id, Integer
        const :event_key, String
        const :action, String
        const :user_id, T.nilable(String), default: nil
        const :channel_id, T.nilable(String), default: nil
        const :post_id, T.nilable(String), default: nil
        const :details, Platform::Json::Scalars
        const :created_at, Time
      end
    end
  end
end
