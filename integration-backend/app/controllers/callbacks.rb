# frozen_string_literal: true

module Controllers
  class Callbacks < Base
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
