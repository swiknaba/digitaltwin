# Standalone packaged-client fixture. No provider or authenticated chat evidence.
require "socket"
require "json"
require "tmpdir"
require "open3"

server = TCPServer.new("127.0.0.1", 0)
url = "http://127.0.0.1:#{server.addr[1]}"
requests = []
fixture = Thread.new do
  3.times do
    connection = server.accept
    method, path = connection.gets.split
    headers = {}
    while (line = connection.gets) && line != "\r\n"
      key, value = line.split(":", 2)
      headers[key.downcase] = value.strip
    end
    body = headers["content-length"] ? JSON.parse(connection.read(headers["content-length"].to_i)) : nil
    requests << [method, path, headers["authorization"], body]
    result, status = case path
                     when "/internal/commander/manifest" then [{ "tools" => [{ "name" => "list_projects" }] }, 200]
                     when "/internal/commander/tools" then [{ "result" => [{ "id" => "fixture-project" }] }, 200]
                     when "/internal/callbacks/artifact-ready" then [{ "status" => "callback_queued" }, 202]
                     else raise "Unexpected fixture path"
                     end
    data = JSON.generate(result)
    connection.write("HTTP/1.1 #{status} OK\r\nContent-Type: application/json\r\nContent-Length: #{data.bytesize}\r\nConnection: close\r\n\r\n#{data}")
    connection.close
  end
end
Dir.mktmpdir do |root|
  token_file = File.join(root, "token")
  File.write(token_file, "fixture-only-capability")
  env = { "DIGITALTWIN_CALLBACK_URL" => url, "DIGITALTWIN_COMMANDER_REQUEST_TOKEN_FILE" => token_file,
          "DIGITALTWIN_SESSION_TOKEN_FILE" => token_file, "DIGITALTWIN_SESSION_GENERATION" => "1" }
  frames = [
    { jsonrpc: "2.0", id: 1, method: "initialize" },
    { jsonrpc: "2.0", id: 2, method: "tools/list" },
    { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "list_projects", arguments: { request_id: "fixture-request" } } }
  ].map { |frame| JSON.generate(frame) + "\n" }.join
  output, error, status = Open3.capture3(env, "/usr/local/bin/digitaltwin-mcp", stdin_data: frames)
  raise "Packaged MCP failed" unless status.success?
  rows = output.lines.map { |line| JSON.parse(line) }
  raise "MCP response mismatch" unless rows[0].dig("result", "serverInfo", "name") == "digitaltwin" && rows[1].dig("result", "tools", 0, "name") == "list_projects" && JSON.parse(rows[2].dig("result", "content", 0, "text")).first["id"] == "fixture-project"
  usage_output, usage_error, usage_status = Open3.capture3(env.merge("DIGITALTWIN_MCP_TOOLSET" => "agentsview_usage"), "/usr/local/bin/digitaltwin-mcp", stdin_data: JSON.generate({ jsonrpc: "2.0", id: 4, method: "tools/list" }) + "\n")
  raise "Packaged AgentsView MCP failed: #{usage_error}" unless usage_status.success?

  usage_rows = usage_output.lines.map { |line| JSON.parse(line) }
  raise "Packaged AgentsView toolset mismatch" unless usage_rows.length == 1 && usage_rows[0].dig("result", "tools")&.map { |tool| tool.fetch("name") } == ["get_usage"]
  output, error, status = Open3.capture3(env, "/usr/local/bin/digitaltwin", "artifact-ready", "--kind", "spec", "--commit", "a" * 40)
  raise "Packaged callback failed" unless status.success?
  fixture.join
  raise "HTTP binding mismatch" unless requests[1][2] == "Bearer fixture-only-capability" && requests[1][3].dig("arguments", "request_id") == "fixture-request" && requests[2][2] == "Bearer fixture-only-capability" && requests[2][3] == { "generation" => 1, "kind" => "spec", "commit" => "a" * 40 }
end
server.close
puts "Packaged stdio MCP and capability callback HTTP fixtures passed; no CLI/provider started"
