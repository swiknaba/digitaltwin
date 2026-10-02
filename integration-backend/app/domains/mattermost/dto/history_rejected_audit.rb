# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    module Dto
      # Audit details of a quarantined chat history post.
      class HistoryRejectedAudit < T::Struct
        include Kirei::Domain::ValueObject

        const :reason, String
      end
    end
  end
end
