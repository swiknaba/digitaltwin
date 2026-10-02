# typed: strict
# frozen_string_literal: true

module Adapters
  module Mattermost
    # Typed API4 facade. Type errors raise Errors::MalformedResponse;
    # transport failures raise Errors::RequestFailed. Unknown fields are ignored.
    class Api
      extend T::Sig

      MALFORMED = "Malformed server response"
      INVALID_REVISION = "Invalid post revision"
      MALFORMED_HISTORY_POST = "Malformed history post"
      MALFORMED_ENVELOPE = "Malformed history envelope; checkpoint retained"
      IDENTIFIER = T.let(/\A[a-z0-9]{26}\z/, Regexp)
      HISTORY_PAGE_SIZE = 200

      sig { params(client: Client).void }
      def initialize(client:)
        @client = client
      end

      sig { params(id: String).returns(Dto::Post) }
      def post(id)
        post_from(@client.get("/api/v4/posts/#{identifier!(id)}"))
      end

      sig { params(id: String).returns(Dto::Channel) }
      def channel(id)
        Dto::Channel.new(id: string(@client.get("/api/v4/channels/#{identifier!(id)}"), "id"))
      end

      sig { params(id: String).returns(Dto::User) }
      def user(id)
        user_from(@client.get("/api/v4/users/#{identifier!(id)}"))
      end

      sig { returns(Dto::User) }
      def me
        user_from(@client.get("/api/v4/users/me"))
      end

      # Absence and transport failure both mean "membership not proven".
      sig { params(channel_id: String, user_id: String).returns(T.nilable(Dto::ChannelMember)) }
      def member(channel_id:, user_id:)
        return nil unless channel_id.match?(IDENTIFIER) && user_id.match?(IDENTIFIER)

        member!(channel_id: channel_id, user_id: user_id)
      rescue Errors::RequestFailed
        nil
      end

      # Raises Errors::RequestFailed with the HTTP status, so callers can tell
      # a revoked membership (403/404) from a transient failure.
      sig { params(channel_id: String, user_id: String).returns(Dto::ChannelMember) }
      def member!(channel_id:, user_id:)
        object = @client.get("/api/v4/channels/#{identifier!(channel_id)}/members/#{identifier!(user_id)}")
        Dto::ChannelMember.new(channel_id: string(object, "channel_id"), user_id: string(object, "user_id"))
      end

      sig { params(new_post: Dto::NewPost).returns(Dto::Post) }
      def create_post(new_post)
        body = { "channel_id" => new_post.channel_id, "root_id" => new_post.root_id, "message" => new_post.message, "props" => new_post.props }
        post_from(@client.post("/api/v4/posts", body))
      end

      # A nil page sends a positive-since query without paging parameters.
      sig { params(channel_id: String, since: Integer, page: T.nilable(Integer)).returns(Dto::HistoryPage) }
      def channel_history(channel_id:, since:, page:)
        params = T.let({ since: since, collapsedThreads: "false" }, T::Hash[Symbol, T.any(Integer, String)])
        if page
          params[:page] = page
          params[:per_page] = HISTORY_PAGE_SIZE
        end
        response = @client.get("/api/v4/channels/#{identifier!(channel_id)}/posts?#{URI.encode_www_form(params)}")
        posts = response["posts"]
        order = response["order"]
        raise Errors::RequestFailed, MALFORMED_ENVELOPE unless posts.is_a?(Hash) && order.is_a?(Array)

        order_ids = order.map { |id| id.is_a?(String) ? id : raise(Errors::RequestFailed, MALFORMED_ENVELOPE) }
        entries = posts.map { |key, raw| history_entry(key.to_s, raw) }
        Dto::HistoryPage.new(order: order_ids, entries: entries)
      end

      # Translates the serialized post carried by a WebSocket event.
      sig { params(serialized: String).returns(Dto::Post) }
      def event_post(serialized:)
        post_from(@client.parse(serialized))
      end

      private

      sig { params(value: String).returns(String) }
      def identifier!(value)
        raise ArgumentError, "Invalid Mattermost identifier" unless value.match?(IDENTIFIER)

        value
      end

      sig { params(key: String, raw: Object).returns(Dto::HistoryEntry) }
      def history_entry(key, raw)
        object = json_object(raw)
        raw_id = object["id"]
        post_id = raw_id.is_a?(String) ? raw_id : nil
        canonical_json = JSON.generate(object)
        begin
          post = post_from(object, malformed: MALFORMED_HISTORY_POST, invalid_revision: MALFORMED_HISTORY_POST)
        rescue Errors::MalformedResponse => error
          return Dto::HistoryEntry.new(key: key, canonical_json: canonical_json, post_id: post_id, post: nil, rejection: error.message)
        end
        Dto::HistoryEntry.new(key: key, canonical_json: canonical_json, post_id: post_id, post: post, rejection: nil)
      end

      sig { params(value: Object).returns(Client::JsonObject) }
      def json_object(value)
        raise Errors::RequestFailed, MALFORMED_ENVELOPE unless value.is_a?(Hash)

        object = T.let({}, Client::JsonObject)
        value.each do |key, item|
          raise Errors::RequestFailed, MALFORMED_ENVELOPE unless key.is_a?(String)

          object[key] = item
        end
        object
      end

      sig { params(object: Client::JsonObject, malformed: String, invalid_revision: String).returns(Dto::Post) }
      def post_from(object, malformed: MALFORMED, invalid_revision: INVALID_REVISION)
        Dto::Post.new(id: string(object, "id", malformed), channel_id: string(object, "channel_id", malformed),
                      user_id: string(object, "user_id", malformed), root_id: optional_string(object, "root_id", malformed),
                      message: string(object, "message", malformed),
                      create_at: non_negative_integer(object, "create_at", invalid_revision),
                      update_at: non_negative_integer(object, "update_at", invalid_revision),
                      delete_at: non_negative_integer(object, "delete_at", invalid_revision),
                      props: props(object, malformed))
      end

      sig { params(object: Client::JsonObject).returns(Dto::User) }
      def user_from(object)
        delete_at = object.key?("delete_at") ? non_negative_integer(object, "delete_at", INVALID_REVISION) : 0
        bot = object.fetch("is_bot", false)
        raise Errors::MalformedResponse, "Unverified bot status" unless bot == true || bot == false

        Dto::User.new(id: string(object, "id"), delete_at: delete_at, bot: bot)
      end

      sig { params(object: Client::JsonObject, key: String, message: String).returns(String) }
      def string(object, key, message = MALFORMED)
        value = object[key]
        raise Errors::MalformedResponse, message unless value.is_a?(String)

        value
      end

      sig { params(object: Client::JsonObject, key: String, message: String).returns(T.nilable(String)) }
      def optional_string(object, key, message)
        value = object[key]
        raise Errors::MalformedResponse, message unless value.nil? || value.is_a?(String)

        value
      end

      sig { params(object: Client::JsonObject, key: String, message: String).returns(Integer) }
      def non_negative_integer(object, key, message)
        value = object[key]
        raise Errors::MalformedResponse, message unless value.is_a?(Integer) && value >= 0

        value
      end

      sig { params(object: Client::JsonObject, message: String).returns(T::Hash[String, String]) }
      def props(object, message)
        value = object["props"]
        return {} if value.nil?
        raise Errors::MalformedResponse, message unless value.is_a?(Hash)

        kept = T.let({}, T::Hash[String, String])
        value.each do |key, item|
          kept[key] = item if key.is_a?(String) && key.start_with?("digitaltwin_") && item.is_a?(String)
        end
        kept
      end
    end
  end
end
