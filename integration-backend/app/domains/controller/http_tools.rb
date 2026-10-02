# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
module Domains
  module Controller
    class HttpTools
      def initialize(url:)
        @base = URI(url)
        raise ArgumentError, "Expected private HTTP(S) base URL" unless %w[http https].include?(@base.scheme) && @base.host && !@base.userinfo && ["", "/"].include?(@base.path) && !@base.query && !@base.fragment
      end

      def definitions = request("GET", "/internal/master/manifest").fetch("tools")
      def call(name, args, token:) = request("POST", "/internal/master/tools", { "name" => name, "arguments" => args }, token).fetch("result")
      private def request(method, path, body = nil, token = nil)
        target = URI.join(@base.to_s, path)
        headers = { "Content-Type" => "application/json" }
        headers["Authorization"] = "Bearer #{token}" if token
        request = (method == "GET" ? Net::HTTP::Get : Net::HTTP::Post).new(target, headers)
        request.body = JSON.generate(body) if body
        response = Net::HTTP.start(target.host, target.port, use_ssl: target.scheme == "https", open_timeout: 5, read_timeout: 10, write_timeout: 10) { |http| http.request(request) }
        raise IOError, "Tool request rejected or uncertain" unless response.code == "200" && response.body.bytesize <= 1_048_576

        JSON.parse(response.body)
      end
    end
  end
end
