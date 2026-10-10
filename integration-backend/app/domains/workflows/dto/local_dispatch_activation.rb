# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # A local operator's explicit acknowledgement after the documented
      # credential-free checks have passed. It is not a provider credential.
      class LocalDispatchActivation < T::Struct
        include Kirei::Domain::ValueObject

        SCHEMA = "digitaltwin.local-dispatch/v1"

        const :schema, String
        const :scope, String
        const :confirmed_at, String
        const :role_config_sha256, String
      end
    end
  end
end
