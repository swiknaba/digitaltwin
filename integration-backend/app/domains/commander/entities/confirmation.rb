# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: confirmations
#
#  id                  :text                not null, primary key
#  requesting_user_id  :text                not null
#  channel_id          :text                not null
#  action              :text                not null
#  parameter_digest    :text                not null
#  expires_at          :timestamp without time zone, not null
#  consumed_at         :timestamp without time zone, null
#  confirming_user_id  :text                null
#  confirming_post_id  :text                null
#

module Domains
  module Commander
    module Entities
      class Confirmation < T::Struct
        include Kirei::Model
        include Kirei::Domain::Entity

        const :id, String
        const :requesting_user_id, String
        const :channel_id, String
        const :action, String
        const :parameter_digest, String
        const :expires_at, Time
        const :consumed_at, T.nilable(Time), default: nil
        const :confirming_user_id, T.nilable(String), default: nil
        const :confirming_post_id, T.nilable(String), default: nil
      end
    end
  end
end
