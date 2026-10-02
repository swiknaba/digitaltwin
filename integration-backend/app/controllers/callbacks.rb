# typed: strict
# frozen_string_literal: true

module Controllers
  class Callbacks < Base
    extend T::Sig

    Response = T.type_alias { Kirei::Routing::RackResponseType }
    Params = T.type_alias { T::Hash[String, Object] }

    class ArtifactCallback < T::Struct
      const :token, String
      const :generation, Integer
      const :kind, String
      const :commit, String
    end

    class ReviewCallback < T::Struct
      const :token, String
      const :generation, Integer
      const :verdict, String
      const :commit, String
    end

    class SayCallback < T::Struct
      const :token, String
      const :generation, Integer
      const :key, String
      const :body, String
    end

    # A missing header is tracked separately so the interactive `say` endpoint
    # can return HTTP 401. The legacy artifact/review callback endpoints remain
    # opaque and map both absent and invalid capabilities to rejection.
    class MissingAuthorization < StandardError; end

    sig { returns(Response) }
    def artifact_ready
      values = request_params
      return unexpected_fields_response unless exact_keys?(values, %w[commit generation kind])

      callback = artifact_callback(values)
      intake.enqueue(token: callback.token, generation: callback.generation, action: "artifact", kind: callback.kind, commit: callback.commit)
      accepted_response
    rescue MissingAuthorization, ArgumentError, Sequel::Error
      rejected_response("Artifact callback rejected")
    end

    sig { returns(Response) }
    def review_ready
      values = request_params
      return unexpected_fields_response unless exact_keys?(values, %w[commit generation verdict])

      callback = review_callback(values)
      intake.enqueue(token: callback.token, generation: callback.generation, action: "review", commit: callback.commit, verdict: callback.verdict)
      accepted_response
    rescue MissingAuthorization, ArgumentError, Sequel::Error
      rejected_response("Review callback rejected")
    end

    sig { returns(Response) }
    def say
      values = request_params
      return unexpected_callback_fields_response unless allowed_keys?(values, %w[generation key text])

      callback = say_callback(values)
      result = Domains::Mattermost::WorkerChat.new(Kirei::App.raw_db_connection).post(
        token: callback.token, generation: callback.generation, key: callback.key, body: callback.body
      )
      render_json({ "status" => result.status, "reason" => result.reason }, status: result.status == "accepted" ? 202 : 403)
    rescue MissingAuthorization
      unauthorized_response
    rescue ArgumentError, Sequel::Error
      render_json({ "status" => "rejected", "reason" => "Invalid callback" }, status: 403)
    end

    private

    sig { returns(Domains::Reviews::Intake) }
    def intake
      Domains::Reviews::Intake.new(Kirei::App.raw_db_connection)
    end

    sig { params(values: Params).returns(ArtifactCallback) }
    def artifact_callback(values)
      ArtifactCallback.new(token: callback_token, generation: integer(values, "generation"), kind: string(values, "kind"), commit: string(values, "commit"))
    end

    sig { params(values: Params).returns(ReviewCallback) }
    def review_callback(values)
      ReviewCallback.new(token: callback_token, generation: integer(values, "generation"), verdict: string(values, "verdict"), commit: string(values, "commit"))
    end

    sig { params(values: Params).returns(SayCallback) }
    def say_callback(values)
      SayCallback.new(token: callback_token, generation: integer(values, "generation"), key: string(values, "key"), body: string(values, "text"))
    end

    sig { params(values: Params, expected: T::Array[String]).returns(T::Boolean) }
    def exact_keys?(values, expected)
      values.keys.sort == expected
    end

    sig { params(values: Params, expected: T::Array[String]).returns(T::Boolean) }
    def allowed_keys?(values, expected)
      (values.keys - expected).empty?
    end

    sig { returns(Params) }
    def request_params
      values = T.let({}, Params)
      params.each do |key, value|
        values[key] = value
      end
      values
    end

    sig { params(values: Params, key: String).returns(String) }
    def string(values, key)
      value = values.fetch(key)
      raise ArgumentError, "Invalid callback" unless value.is_a?(String)

      value
    end

    sig { params(values: Params, key: String).returns(Integer) }
    def integer(values, key)
      value = values.fetch(key)
      raise ArgumentError, "Invalid callback" unless value.is_a?(Integer)

      value
    end

    sig { returns(String) }
    def callback_token
      value = request.env["HTTP_AUTHORIZATION"]
      raise MissingAuthorization, "Session authorization required" unless value.is_a?(String) && value.start_with?("Bearer ")

      value.delete_prefix("Bearer ")
    end

    sig { returns(Response) }
    def accepted_response
      render_json({ "status" => "callback_queued" }, status: 202)
    end

    sig { params(message: String).returns(Response) }
    def rejected_response(message)
      render_json({ "error" => message }, status: 403)
    end

    sig { returns(Response) }
    def unauthorized_response
      render_json({ "error" => "Session authorization required" }, status: 401)
    end

    sig { returns(Response) }
    def unexpected_fields_response
      render_json({ "error" => "Unexpected fields" }, status: 400)
    end

    sig { returns(Response) }
    def unexpected_callback_fields_response
      render_json({ "error" => "Unexpected callback fields" }, status: 400)
    end
  end
end
