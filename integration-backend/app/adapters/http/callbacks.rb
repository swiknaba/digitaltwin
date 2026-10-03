# typed: strict
# frozen_string_literal: true

module Adapters
  module Http
    class Callbacks < Base
      Response = T.type_alias { Kirei::Routing::RackResponseType }
      Params = T.type_alias { T::Hash[String, Object] }

      sig { returns(Response) }
      def artifact_ready
        values = request_params
        return unexpected_fields_response unless exact_keys?(values, %w[commit generation kind])

        callback = artifact_callback(values)
        queued = queue_callback.call(token: callback.token, generation: callback.generation, action: "artifact", kind: callback.kind, commit: callback.commit)
        queued.success? ? accepted_response : rejected_response("Artifact callback rejected")
      rescue Errors::MissingAuthorization, ArgumentError, Sequel::Error
        rejected_response("Artifact callback rejected")
      end

      sig { returns(Response) }
      def review_ready
        values = request_params
        return unexpected_fields_response unless exact_keys?(values, %w[commit generation verdict])

        callback = review_callback(values)
        queued = queue_callback.call(token: callback.token, generation: callback.generation, action: "review", commit: callback.commit, verdict: callback.verdict)
        queued.success? ? accepted_response : rejected_response("Review callback rejected")
      rescue Errors::MissingAuthorization, ArgumentError, Sequel::Error
        rejected_response("Review callback rejected")
      end

      sig { returns(Response) }
      def say
        values = request_params
        return unexpected_callback_fields_response unless allowed_keys?(values, %w[generation key text])

        callback = say_callback(values)
        result = Services::Sessions::PostWorkerChat.new.call(token: callback.token, generation: callback.generation, key: callback.key, body: callback.body)
        return render_json({ "status" => "accepted", "reason" => "Queued in bound thread" }, status: 202) if result.success?

        render_json({ "status" => "rejected", "reason" => result.errors.first&.detail.to_s }, status: 403)
      rescue Errors::MissingAuthorization
        unauthorized_response
      rescue ArgumentError, Sequel::Error
        render_json({ "status" => "rejected", "reason" => "Invalid callback" }, status: 403)
      end

      sig { returns(Services::Reviews::QueueCallback) }
      private def queue_callback
        Services::Reviews::QueueCallback.new
      end

      sig { params(values: Params).returns(Dto::ArtifactCallback) }
      private def artifact_callback(values)
        Dto::ArtifactCallback.new(token: callback_token, generation: integer(values, "generation"), kind: string(values, "kind"), commit: string(values, "commit"))
      end

      sig { params(values: Params).returns(Dto::ReviewCallback) }
      private def review_callback(values)
        Dto::ReviewCallback.new(token: callback_token, generation: integer(values, "generation"), verdict: string(values, "verdict"), commit: string(values, "commit"))
      end

      sig { params(values: Params).returns(Dto::SayCallback) }
      private def say_callback(values)
        Dto::SayCallback.new(token: callback_token, generation: integer(values, "generation"), key: string(values, "key"), body: string(values, "text"))
      end

      sig { params(values: Params, expected: T::Array[String]).returns(T::Boolean) }
      private def exact_keys?(values, expected)
        values.keys.sort == expected
      end

      sig { params(values: Params, expected: T::Array[String]).returns(T::Boolean) }
      private def allowed_keys?(values, expected)
        (values.keys - expected).empty?
      end

      sig { returns(Params) }
      private def request_params
        values = T.let({}, Params)
        params.each do |key, value|
          values[key] = value
        end
        values
      end

      sig { params(values: Params, key: String).returns(String) }
      private def string(values, key)
        value = values.fetch(key)
        raise ArgumentError, "Invalid callback" unless value.is_a?(String)

        value
      end

      sig { params(values: Params, key: String).returns(Integer) }
      private def integer(values, key)
        value = values.fetch(key)
        raise ArgumentError, "Invalid callback" unless value.is_a?(Integer)

        value
      end

      sig { returns(String) }
      private def callback_token
        value = request.env["HTTP_AUTHORIZATION"]
        raise Errors::MissingAuthorization, "Session authorization required" unless value.is_a?(String) && value.start_with?("Bearer ")

        value.delete_prefix("Bearer ")
      end

      sig { returns(Response) }
      private def accepted_response
        render_json({ "status" => "callback_queued" }, status: 202)
      end

      sig { params(message: String).returns(Response) }
      private def rejected_response(message)
        render_json({ "error" => message }, status: 403)
      end

      sig { returns(Response) }
      private def unauthorized_response
        render_json({ "error" => "Session authorization required" }, status: 401)
      end

      sig { returns(Response) }
      private def unexpected_fields_response
        render_json({ "error" => "Unexpected fields" }, status: 400)
      end

      sig { returns(Response) }
      private def unexpected_callback_fields_response
        render_json({ "error" => "Unexpected callback fields" }, status: 400)
      end
    end
  end
end
