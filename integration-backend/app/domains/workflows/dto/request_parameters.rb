# typed: strict
# frozen_string_literal: true

module Domains
  module Workflows
    module Dto
      # The `workflow_requests.parameters` JSONB object. Its serialized form
      # feeds the start request digest, so it keeps today's keys and order.
      class RequestParameters < T::Struct
        extend T::Sig
        include Kirei::Domain::ValueObject

        const :title, String
        const :existing_thread, T.nilable(String)
        const :roles, RoleAssignments

        # Keeps "existing_thread" present as null, as the digest input requires.
        # `super` keeps unknown stored keys, so Records can detect them.
        sig { params(strict: T::Boolean).returns(T::Hash[String, T.any(String, NilClass, T::Hash[String, T::Hash[String, T.any(String, T::Array[String])]])]) }
        def serialize(strict = true) = { "title" => title, "existing_thread" => existing_thread }.merge(super)
      end
    end
  end
end
