# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class Listener
      class VerificationTransport
        include VerifiedDelivery::Transport
        extend T::Sig

        sig { params(client: Client).void }
        def initialize(client)
          @client = T.let(client, Client)
        end

        sig { override.params(path: String).returns(VerifiedDelivery::TransportResponse) }
        def get(path)
          raw = @client.get(path)
          response = T.let({}, VerifiedDelivery::TransportResponse)
          raw.each { |key, value| response[key] = verification_value(value) }
          response
        end

        private

        sig { params(value: Object).returns(VerifiedDelivery::TransportValue) }
        def verification_value(value)
          return value if value.is_a?(String) || value.is_a?(Integer) || value == true || value == false || value.nil?

          raise Client::Error, "Malformed Mattermost verification response"
        end
      end
    end
  end
end
