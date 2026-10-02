# typed: strict
# frozen_string_literal: true

require "json"
require "stringio"

# Kirei 0.10.0 stores env on its singleton router. Thread#[] is fiber-local
# under Ruby, so each Falcon request retains its own authentication context.
module RequestLocalRouter
  extend T::Sig

  Environment = T.type_alias { T::Hash[String, Object] }

  sig { returns(T.nilable(Environment)) }
  def current_env
    Thread.current[:digitaltwin_rack_env]
  end

  sig { params(env: T.nilable(Environment)).returns(T.nilable(Environment)) }
  def current_env=(env)
    Thread.current[:digitaltwin_rack_env] = env
  end
end
Kirei::Routing::Router.prepend(RequestLocalRouter)

module RackBoundary
  Endpoint = T.type_alias { T.any(Proc, Method) }
  Response = T.type_alias { Kirei::Routing::RackResponseType }
end

class RackCompatibility
  extend T::Sig

  MAX_BODY = 65_536
  sig { params(app: RackBoundary::Endpoint).void }
  def initialize(app)
    @app = app
  end

  sig { params(env: RequestLocalRouter::Environment).returns(RackBoundary::Response) }
  def call(env)
    previous = Kirei::Routing::Router.instance.current_env
    normalized = env.dup
    normalized["REQUEST_PATH"] ||= env.fetch("PATH_INFO")
    if %w[POST PUT PATCH].include?(env["REQUEST_METHOD"])
      body = rack_body(env["rack.input"])
      return error(413, "Request body too large") if body.bytesize > MAX_BODY

      value = parse_object(body)
      return error(400, "JSON body must be an object") if value.nil?

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

  private

  sig { params(input: Object).returns(String) }
  def rack_body(input)
    case input
    when NilClass then ""
    when StringIO, Protocol::Rack::Input then input.read(MAX_BODY + 1)
    else
      raise ArgumentError, "rack.input must be readable"
    end
  end

  sig { params(body: String).returns(T.nilable(T::Hash[String, Object])) }
  def parse_object(body)
    return {} if body.empty?

    parsed = JSON.parse(body)
    parsed if parsed.is_a?(Hash) && parsed.keys.all? { |key| key.is_a?(String) }
  end

  sig { params(status: Integer, message: String).returns(RackBoundary::Response) }
  def error(status, message)
    [status, { "content-type" => "application/json" }, [JSON.generate({ "error" => message })]]
  end
end
