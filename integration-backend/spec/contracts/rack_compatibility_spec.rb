# frozen_string_literal: true

require "rspec"
require "rack/mock"
require "async"
require "protocol/rack/input"
require "protocol/http/body/buffered"
require_relative "../../app"

class IsolationController < Kirei::Controller
  def echo
    # Delay first request before consulting request context, as authentication may do.
    Fiber.yield if Thread.current[:test_fiber]
    Thread.current[:test_entered]&.push(true)
    Thread.current[:test_release]&.pop
    render_json({ "auth" => request.env["HTTP_AUTHORIZATION"], "params" => params })
  end

  def crash
    raise "test exception"
  end
end
Kirei::Routing::Router.add_routes(["GET", "POST", "PUT", "PATCH"].map { |verb|
  Kirei::Routing::Route.new(verb: Kirei::Routing::Verb.deserialize(verb), path: "/test/echo",
                            controller: IsolationController, action: "echo")
} + [Kirei::Routing::Route.new(verb: Kirei::Routing::Verb::GET, path: "/test/crash", controller: IsolationController,
                               action: "crash")])

RSpec.describe "Kirei Rack compatibility" do
  def env(method: "GET", input: nil, auth: "first")
    Rack::MockRequest.env_for("http://localhost/test/echo", method: method).merge(
      "REQUEST_PATH" => "/test/echo", "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_AUTHORIZATION" => auth, "rack.input" => input
    )
  end
  let(:app) { Digitaltwin.new }
  def json(response) = JSON.parse(response[2].join)

  it "isolates overlapping fibers' authentication and clears context" do
    a = Fiber.new { Thread.current[:test_fiber] = true; app.call(env) }
    b = Fiber.new { app.call(env(auth: "second")) }
    a.resume
    expect(json(b.resume)["auth"]).to eq("second")
    expect(json(a.resume)["auth"]).to eq("first")
    expect(Kirei::Routing::Router.instance.current_env).to be_nil
  end

  it "isolates overlapping threads' authentication" do
    entered, release = Queue.new, Queue.new
    first = Thread.new {
      Thread.current[:test_entered] = entered; Thread.current[:test_release] = release; app.call(env)
    }
    entered.pop
    expect(json(app.call(env(auth: "second")))["auth"]).to eq("second")
    release.push(true)
    expect(json(first.value)["auth"]).to eq("first")
  end

  it "cleans up context after an exception" do
    expect(app.call(env.merge("REQUEST_PATH" => "/test/crash"))[0]).to eq(500)
    expect(Kirei::Routing::Router.instance.current_env).to be_nil
  end

  %w[POST PUT PATCH].each do |verb|
    it "accepts Falcon input for #{verb}" do
      input = Protocol::Rack::Input.new(Protocol::HTTP::Body::Buffered.new(['{"hello":"world"}']))
      result = app.call(env(method: verb, input: input))
      expect(result[0]).to eq(200)
      expect(json(result)["params"]).to eq("hello" => "world")
    end
    it "handles absent and empty #{verb} bodies" do
      [nil, StringIO.new("")].each { |input| expect(app.call(env(method: verb, input: input))[0]).to eq(200) }
    end
    it "rejects malformed and non-object #{verb} JSON" do
      ["{", "[]", "null"].each { |body| expect(app.call(env(method: verb, input: StringIO.new(body)))[0]).to eq(400) }
    end
    it "bounds #{verb} bodies without trusting content length" do
      expect(app.call(env(method: verb, input: StringIO.new("x" * 65_537)))[0]).to eq(413)
    end
  end
end
