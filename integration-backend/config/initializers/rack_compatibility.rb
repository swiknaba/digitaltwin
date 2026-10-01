# frozen_string_literal: true

require "json"
require "stringio"

# Kirei 0.10.0 stores env on its singleton router. Thread#[] is fiber-local
# under Ruby, so each Falcon request retains its own authentication context.
module RequestLocalRouter
  def current_env = Thread.current[:digitaltwin_rack_env]

  def current_env=(env)
    Thread.current[:digitaltwin_rack_env] = env
  end
end
Kirei::Routing::Router.prepend(RequestLocalRouter)

class RackCompatibility
  MAX_BODY = 65_536
  def initialize(app) = @app = app

  def call(env)
    previous = Kirei::Routing::Router.instance.current_env
    normalized = env.dup
    normalized["REQUEST_PATH"] ||= env.fetch("PATH_INFO")
    if %w[POST PUT PATCH].include?(env["REQUEST_METHOD"])
      input = env["rack.input"]
      body = input ? input.read(MAX_BODY + 1).to_s : ""
      return error(413, "Request body too large") if body.bytesize > MAX_BODY

      value = body.empty? ? {} : JSON.parse(body)
      return error(400, "JSON body must be an object") unless value.is_a?(Hash)

      # Narrow normalization keeps upstream routing untouched and accepts
      # Protocol::Rack::Input, which is readable but is not IO/StringIO.
      normalized["rack.input"] = StringIO.new(JSON.generate(value))
    end
    @app.call(normalized)
  rescue JSON::ParserError
    error(400, "Malformed JSON")
  ensure
    Kirei::Routing::Router.instance.current_env = previous
  end
  private def error(status, message)
    [status, { "content-type" => "application/json" }, [JSON.generate({ "error" => message })]]
  end
end
