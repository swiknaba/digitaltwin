require_relative "../spec_helper"
require "rack/mock"
RSpec.describe "Process startup" do
  it "reuses generated live and database ready routes" do
    request = Rack::MockRequest.new(Digitaltwin.new)
    expect(request.get("/livez", "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1").status).to eq(200)
    expect(request.get("/readyz", "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1").status).to eq(200)
    allow(Kirei::App).to receive(:raw_db_connection).and_raise(Sequel::DatabaseConnectionError, "fixture unavailable")
    expect(request.get("/readyz", "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1").status).to eq(503)
  end
  it "rejects every role before serving when migrations are pending" do
    Kirei::App.raw_db_connection[:schema_info].update(version: 0)
    %w[web worker chat-listener].each do |role|
      output, status = Open3.capture2e({ "BOOT_CHECK_ONLY" => "1" }, "ruby", "bin/#{role}")
      expect(status.success?).to be(false)
      expect(output).to include("Pending migrations")
    end
  ensure
    Kirei::App.raw_db_connection[:schema_info].update(version: 8)
  end
end
