# typed: strict
# frozen_string_literal: true

require "json"
require "openssl"

module Adapters
  module FutureTasks
    # HMAC verifier for operator-issued, one-use bridge capabilities. Issuance and
    # key rotation remain operator concerns; Kirei only consumes valid tokens.
    class CapabilityVerifier
      extend T::Sig

      MAXIMUM_LIFETIME_SECONDS = 300

      sig { params(secret: String).void }
      def initialize(secret:)
        @secret = secret
      end

      sig { params(token: String, audience: String, now: Time).returns(Capability) }
      def verify!(token:, audience:, now: Time.now)
        encoded, signature = token.split(".", 2)
        raise ArgumentError, "Malformed future-task capability" unless encoded && signature

        expected = OpenSSL::HMAC.hexdigest("SHA256", @secret, encoded)
        raise ArgumentError, "Invalid future-task capability" unless secure_equal?(expected, signature)

        payload = JSON.parse([encoded].pack("H*").force_encoding(Encoding::UTF_8))
        raise ArgumentError, "Malformed future-task capability" unless payload.is_a?(Hash)
        raise ArgumentError, "Capability audience is invalid" unless payload.fetch("aud") == audience

        issued_at = Time.at(Integer(payload.fetch("iat")))
        expires_at = Time.at(Integer(payload.fetch("exp")))
        raise ArgumentError, "Capability issued in the future" if issued_at > now
        raise ArgumentError, "Capability expired" unless expires_at > now
        raise ArgumentError, "Capability lifetime is invalid" if expires_at - issued_at > MAXIMUM_LIFETIME_SECONDS

        capability = Capability.new(id: String(payload.fetch("jti")), actor_id: String(payload.fetch("actor")), conversation_id: String(payload.fetch("conversation")), owner: payload.fetch("owner") == true)
        raise ArgumentError, "Capability values are invalid" if capability.id.empty? || capability.actor_id.empty? || capability.conversation_id.empty?

        database[:future_task_capability_uses].insert(id: SecureRandom.uuid, capability_id: capability.id, actor_id: capability.actor_id,
                                                      conversation_id: capability.conversation_id, used_at: now)
        capability
      rescue KeyError, ArgumentError, JSON::ParserError => error
        raise ArgumentError, error.message
      rescue Sequel::UniqueConstraintViolation
        raise ArgumentError, "Capability was already used"
      end

      sig { params(left: String, right: String).returns(T::Boolean) }
      private def secure_equal?(left, right)
        left.bytesize == right.bytesize && OpenSSL.fixed_length_secure_compare(left, right)
      end

      sig { returns(Sequel::Database) }
      private def database = Kirei::App.raw_db_connection
    end
  end
end
