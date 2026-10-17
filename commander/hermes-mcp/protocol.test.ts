import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { once } from "node:events"
import test from "node:test"

test("serves an actual stdio MCP initialize and the four allowlisted Commander tools without an OpenCode credential", async () => {
  const child = spawn(process.execPath, ["commander/hermes-mcp/server.ts"], {
    cwd: process.cwd(),
    env: { ...process.env, DIGITALTWIN_HERMES_DELEGATION_STATE: `${process.cwd()}/local/tmp/hermes-mcp-protocol-test.json` },
    stdio: ["pipe", "pipe", "pipe"],
  })
  const output: Buffer[] = []
  child.stdout.on("data", (chunk: Buffer) => output.push(chunk))
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-03-26" } })}\n`)
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list" })}\n`)
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "commander_list_projects", arguments: {} } })}\n`)
  child.stdin.end()
  const [code] = await once(child, "close") as [number]
  assert.equal(code, 0)
  const messages = Buffer.concat(output).toString("utf8").trim().split("\n").map((line) => JSON.parse(line) as { id: number; result?: unknown; error?: { message: string } })
  const initialized = messages.find((item) => item.id === 1)
  assert.deepEqual(initialized?.result, {
    protocolVersion: "2025-03-26",
    capabilities: { tools: { listChanged: false } },
    serverInfo: { name: "digitaltwin-commander-delegation", version: "1.0.0" },
  })
  const toolResult = messages.find((item) => item.id === 2)?.result as { tools: Array<{ name: string }> }
  assert.deepEqual(toolResult.tools.map((item) => item.name), [
    "commander_list_projects",
    "commander_create_project_session",
    "commander_read_agent",
    "commander_continue_agent",
  ])
  assert.match(messages.find((item) => item.id === 3)?.error?.message ?? "", /service registration access is not configured/)
})
