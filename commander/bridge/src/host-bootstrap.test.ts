import assert from "node:assert/strict"
import test from "node:test"
import { commanderPanelFromHostBootstrap, installHostOperatorBootstrap, resetHostOperatorBootstrapForTest } from "./host-bootstrap.ts"
import { CommanderMainProcessPanel } from "./main-process-panel.ts"
import { CommanderMainProcessTransport } from "./main-process-transport.ts"
import { commanderConversationId, streamCursor } from "./contract.ts"

test("host bootstrap defaults closed and cannot be replaced", () => {
  resetHostOperatorBootstrapForTest()
  assert.deepEqual(commanderPanelFromHostBootstrap().snapshot(), { status: "not-configured", events: [] })
  const panel = new CommanderMainProcessPanel(undefined)
  installHostOperatorBootstrap({ createPanel: () => panel })
  assert.equal(commanderPanelFromHostBootstrap(), panel)
  assert.throws(() => installHostOperatorBootstrap({ createPanel: () => new CommanderMainProcessPanel(undefined) }), /already installed/)
  resetHostOperatorBootstrapForTest()
})

test("host-installed panel drives open, send, steer, cancel, and reconnect without leaking its proof", async () => {
  resetHostOperatorBootstrapForTest()
  const conversation = {
    id: commanderConversationId("commander:global"),
    version: 1,
    status: "ready" as const,
    lastCursor: streamCursor(0),
    events: [],
    requests: [],
  }
  const actions: string[] = []
  const responses: unknown[] = [
    { ok: true, actorId: "operator", conversation },
    { ok: true, conversation, events: [], resyncRequired: false },
    { ok: true, state: "dispatched" },
    { ok: true, state: "dispatched" },
    { ok: true, state: "dispatched" },
    { ok: true, conversation, events: [], resyncRequired: false },
  ]
  const panel = new CommanderMainProcessPanel(new CommanderMainProcessTransport({
    baseUrl: "http://127.0.0.1:4312",
    capabilityIssuer: { issue: async (input) => { actions.push(input.action); return { token: "host-only-proof" } } },
    fetch: { fetch: async () => ({ status: 200, json: async () => responses.shift() ?? {} }) },
  }))
  installHostOperatorBootstrap({ createPanel: () => panel })

  const fromHost = commanderPanelFromHostBootstrap()
  assert.equal((await fromHost.open()).status, "active")
  assert.equal((await fromHost.prompt("send this")).status, "active")
  assert.equal((await fromHost.steer("be brief")).status, "active")
  assert.equal((await fromHost.cancel()).status, "active")
  assert.equal((await fromHost.reconnect(streamCursor(0))).status, "active")
  assert.deepEqual(actions, ["read", "read", "prompt", "steer", "cancel", "read"])
  assert.equal(JSON.stringify(fromHost.snapshot()).includes("host-only-proof"), false)
  resetHostOperatorBootstrapForTest()
})
