# frozen_string_literal: true

module Controllers
  class Master < Base
    def manifest
      definitions = Domains::Controller::Tools.new(nil, services: nil, requests: nil).definitions
      render_json({ "tools" => definitions }, status: 200)
    end

    def tools
      return render_json({ "error" => "Unexpected fields" }, status: 400) unless params.keys.sort == %w[arguments name]

      db = Kirei::App.raw_db_connection
      services = Domains::Controller::Services.from_env(db)
      requests = Domains::Controller::Requests.new(db, source: services.source)
      value = Domains::Controller::Tools.new(db, services: services, requests: requests).call(params["name"], params["arguments"], token: bearer)
      render_json({ "result" => value }, status: 200)
    rescue StandardError
      render_json({ "error" => "Request rejected" }, status: 403)
    end

    def reply
      return render_json({ "error" => "Unexpected fields" }, status: 400) unless params.keys.sort == %w[request_id text]

      services = Domains::Controller::Services.from_env(Kirei::App.raw_db_connection)
      raise ArgumentError, "Master not configured" unless services.master

      services.master.reply(request_id: params["request_id"], token: bearer, text: params["text"])
      render_json({ "status" => "queued" }, status: 202)
    rescue StandardError
      render_json({ "error" => "Request rejected" }, status: 403)
    end
    private def bearer
      header = request.env["HTTP_AUTHORIZATION"].to_s
      raise ArgumentError, "Request authorization required" unless header.start_with?("Bearer ") && header.length > 7

      header.delete_prefix("Bearer ")
    end
  end
end
