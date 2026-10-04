# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: memory_operations
#
#  id                  :text                not null, primary key
#  entry_id            :text                not null
#  scope               :text                not null
#  project_id          :text                null
#  idempotency_key     :text                not null
#  kind                :text                not null
#  created_at          :timestamp without time zone, not null
#

module Domains
  module Memory
    module Entities
      class MemoryOperation < T::Struct
        extend T::Sig
        include Kirei::Model
        include Kirei::Domain::Entity

        sig { override.returns(String) }
        def self.table_name = "memory_operations"

        const :id, String
        const :entry_id, String
        const :scope, Dto::MemoryScope
        const :project_id, T.nilable(String)
        const :idempotency_key, String
        const :kind, String
        const :created_at, Time
      end
    end
  end
end
