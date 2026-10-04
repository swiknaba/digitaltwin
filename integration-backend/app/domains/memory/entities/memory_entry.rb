# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: memory_entries
#
#  id                  :text                not null, primary key
#  scope               :text                not null
#  project_id          :text                null
#  content             :text                not null
#  source              :text                not null
#  revision            :integer             not null
#  created_at          :timestamp without time zone, not null
#  updated_at          :timestamp without time zone, not null
#

module Domains
  module Memory
    module Entities
      class MemoryEntry < T::Struct
        extend T::Sig
        include Kirei::Model
        include Kirei::Domain::Entity

        sig { override.returns(String) }
        def self.table_name = "memory_entries"

        const :id, String
        const :scope, Dto::MemoryScope
        const :project_id, T.nilable(String)
        const :content, String
        const :source, String
        const :revision, Integer
        const :created_at, Time
        const :updated_at, Time
      end
    end
  end
end
