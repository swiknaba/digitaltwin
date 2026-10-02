# frozen_string_literal: true

module Controllers
  class Callbacks < Base
    def artifact_ready
      return render_json({ "error" => "Unexpected fields" }, status: 400) unless params.keys.sort == %w[commit generation kind]

      intake.enqueue(token: callback_token, generation: params["generation"], action: "artifact", kind: params["kind"], commit: params["commit"])
      render_json({ "status" => "callback_queued" }, status: 202)
    rescue StandardError
      render_json({ "error" => "Artifact callback rejected" }, status: 403)
    end

    def review_ready
      return render_json({ "error" => "Unexpected fields" }, status: 400) unless params.keys.sort == %w[commit generation verdict]

      intake.enqueue(token: callback_token, generation: params["generation"], action: "review", commit: params["commit"], verdict: params["verdict"])
      render_json({ "status" => "callback_queued" }, status: 202)
    rescue StandardError
      render_json({ "error" => "Review callback rejected" }, status: 403)
    end
    private def intake = Domains::Reviews::Intake.new(Kirei::App.raw_db_connection)
    private def callback_token
      header = request.env["HTTP_AUTHORIZATION"].to_s
      raise ArgumentError, "Session authorization required" unless header.start_with?("Bearer ")

      header.delete_prefix("Bearer ")
    end

    def say
      return render_json({ "error" => "Unexpected callback fields" },
                         status: 400) unless (params.keys - %w[generation key
                                                               text]).empty?

      auth = request.env["HTTP_AUTHORIZATION"].to_s
      return render_json({ "error" => "Session authorization required" },
                         status: 401) unless auth.start_with?("Bearer ")

      result = Domains::Mattermost::WorkerChat.new(Kirei::App.raw_db_connection).post(
        token: auth.delete_prefix("Bearer "), generation: params["generation"], key: params["key"], body: params["text"]
      )
      render_json({ "status" => result.status, "reason" => result.reason },
                  status: result.status == "accepted" ? 202 : 403)
    end
  end
end
