# typed: strict
# frozen_string_literal: true

module Domains
  module Projects
    module Dto
      # A chat channel enrolled to one GitHub repository checkout.
      class Project < T::Struct
        include Kirei::Domain::ValueObject

        const :id, String
        const :channel_id, String
        const :slug, String
        const :remote_identity, String
        const :workspace, String
      end
    end
  end
end
