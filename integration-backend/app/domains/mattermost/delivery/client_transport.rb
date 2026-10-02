# typed: strict
# frozen_string_literal: true

module Domains
  module Mattermost
    class Delivery
      class ClientTransport
        include Transport
        extend T::Sig

        sig { params(client: Client).void }
        def initialize(client)
          @client = T.let(client, Client)
        end

        sig { override.params(path: String).returns(GetResponse) }
        def get(path)
          raw = T.let(@client.get(path), Object)
          return post_list_response(raw) if raw.is_a?(Hash) && raw.key?("posts")

          response(raw)
        end

        sig { override.params(path: String, body: PostPayload).returns(Response) }
        def post(path, body)
          response(@client.post(path, body))
        end

        private

        sig { params(value: Object).returns(Response) }
        def response(value)
          raise ArgumentError, "Malformed Mattermost response" unless value.is_a?(Hash)

          response = T.let({}, Response)
          value.each do |key, item|
            raise ArgumentError, "Malformed Mattermost response" unless key.is_a?(String) && response_value?(item)

            response[key] = item
          end
          response
        end

        sig { params(value: Object).returns(T::Boolean) }
        def response_value?(value)
          value.is_a?(String) || value.is_a?(Integer) || value == true || value == false || value.nil? ||
            (value.is_a?(Hash) && value.all? { |key, item| key.is_a?(String) && item.is_a?(String) })
        end

        sig { params(value: Object).returns(T::Hash[String, PostList]) }
        def post_list_response(value)
          raise ArgumentError, "Malformed Mattermost post list" unless value.is_a?(Hash)

          posts = value.fetch("posts")
          raise ArgumentError, "Malformed Mattermost post list" unless posts.is_a?(Hash)

          list = T.let({}, PostList)
          posts.each do |id, post|
            raise ArgumentError, "Malformed Mattermost post list" unless id.is_a?(String)

            list[id] = response(post)
          end
          { "posts" => list }
        end
      end
    end
  end
end
