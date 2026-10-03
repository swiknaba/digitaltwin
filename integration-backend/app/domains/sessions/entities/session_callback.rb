# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: callbacks
#
#  id                  :text                not null, primary key
#  session_id          :text                not null
#  generation          :integer             not null
#  key                 :text                not null
#  body_digest         :text                not null
#

module Domains
  module Sessions
    module Entities
      # Receipt of one Worker callback key per session generation.
      class SessionCallback < T::Struct
        extend T::Sig
        include Kirei::Model
        include Kirei::Domain::Entity

        sig { override.returns(String) }
        def self.table_name = "callbacks"

        # Same ids as the former raw insert (`callback_` + 12 characters).
        sig { override.returns(String) }
        def self.human_id_prefix = "callback"

        const :id, String
        const :session_id, String
        const :generation, Integer
        const :key, String
        const :body_digest, String
      end
    end
  end
end
