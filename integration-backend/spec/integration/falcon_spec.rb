require_relative "../spec_helper"
require "socket"
require "net/http"
RSpec.describe "Actual Falcon HTTP server" do
  it "serves concurrent health requests and normalizes real protocol bodies" do
    reserve = TCPServer.new("127.0.0.1", 0)
    port = reserve.addr[1]
    reserve.close
    log = File.join(Dir.tmpdir, "digitaltwin-falcon-#{Process.pid}.log")
    pid = Process.spawn({ "PORT" => port.to_s, "RACK_ENV" => "production" }, "ruby", "bin/web", out: log, err: [:child, :out],
                                                                                                pgroup: true)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    loop do
      begin
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/readyz"))
        break if response.code == "200"
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      end
      raise File.read(log) if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
    responses = 10.times.map {
      Thread.new {
        Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/livez"))
      }
    }.map(&:value)
    expect(responses.map(&:code).uniq).to eq(["200"])
    expect(responses.map { |r| r["x-request-id"] }.uniq.size).to eq(10)
    ["", '{"generation":1,"key":"message","text":"hello"}', "{", "[]",
     "x" * 65_537].zip(%w[401 401 400 400 413]).each do |body, status|
      target = URI("http://127.0.0.1:#{port}/internal/callbacks/say")
      response = Net::HTTP.post(target, body, { "Content-Type" => "application/json" })
      expect(response.code).to eq(status)
    end
  ensure
    if pid
      Process.kill("TERM", -pid) rescue Errno::ESRCH
      Process.wait(pid) rescue Errno::ECHILD
    end
    File.delete(log) if log && File.exist?(log)
  end
end
