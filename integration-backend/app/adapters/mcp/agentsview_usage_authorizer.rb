# typed: strict
# frozen_string_literal: true

module Adapters
  module Mcp
    # Minimal callback client for the aggregate-only usage server. It can only
    # prove the live request capability; it cannot enumerate or invoke tools.
    class AgentsviewUsageAuthorizer
      extend T::Sig
      include AgentsviewUsageAuthorizerInterface

      sig { params(url: String).void }
      def initialize(url:)
        @base = T.let(URI(url), URI::Generic)
        valid = %w[http https].include?(@base.scheme) && @base.host && !@base.userinfo && ["", "/"].include?(@base.path) && !@base.query && !@base.fragment
        raise ArgumentError, "Expected private HTTP(S) base URL" unless valid
      end

      sig { override.params(token: String).void }
      def authorize(token:)
        target = URI.join(@base.to_s, "/internal/commander/authorize")
        request = Net::HTTP::Post.new(target, { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" })
        request.body = "{}"
        response = Net::HTTP.start(target.host, target.port, use_ssl: target.scheme == "https", open_timeout: 5, read_timeout: 10, write_timeout: 10) { |http| http.request(request) }
        raise IOError, "Usage request capability rejected or uncertain" unless response.code == "200" && response.body.bytesize <= 1_048_576

        parsed = JSON.parse(response.body)
        raise ArgumentError, "Usage request capability response is invalid" unless parsed.is_a?(Hash) && parsed == { "status" => "authorized" }
      rescue JSON::ParserError
        raise ArgumentError, "Usage request capability response is invalid"
      end
    end
  end
end
