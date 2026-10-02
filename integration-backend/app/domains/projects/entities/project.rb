# typed: strict
# frozen_string_literal: true

# == Schema Info
#
# Table name: projects
#
#  id                  :text                not null, primary key
#  channel_id          :text                not null
#  slug                :text                not null
#  remote_identity     :text                not null
#  workspace           :text                not null
#  created_at          :timestamp without time zone, not null
#

module Domains
  module Projects
    module Entities
      # created_at is set by the column default and is not modelled.
      class Project < T::Struct
        extend T::Sig
        include Kirei::Model

        # Project ids appear in chat and branch names; 12 characters keep them collision-free.
        sig { override.returns(Integer) }
        def self.human_id_length = 12
        include Kirei::Domain::Entity

        const :id, String
        const :channel_id, String
        const :slug, String
        const :remote_identity, String
        const :workspace, String
      end
    end
  end
end
