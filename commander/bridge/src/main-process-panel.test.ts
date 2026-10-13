import assert from "node:assert/strict"
import test from "node:test"
import { commanderConversationId, streamCursor } from "./contract.ts"
import { CommanderMainProcessPanel } from "./main-process-panel.ts"
import { CommanderMainProcessTransport } from "./main-process-transport.ts"

test("panel adapter invokes the main-only transport and retains replayed events without proofs", async () => {
  const conversation = { id: commanderConversationId("commander:global"), version: 1, status: "ready" as const, lastCursor: streamCursor(0), events: [], requests: [] }
  const actions: string[] = []
  const responses: unknown[] = [
    { ok: true, actorId: "owner-1", conversation },
    { ok: true, conversation, events: [], resyncRequired: false },
    { ok: true, state: "dispatched" },
    { ok: true, state: "dispatched" },
    { ok: true, state: "dispatched" },
  ]
  const transport = new CommanderMainProcessTransport({
    baseUrl: "http://127.0.0.1:4312",
    capabilityIssuer: { issue: async (input) => { actions.push(input.action); return { token: "main-only-proof" } } },
    fetch: { fetch: async () => ({ status: 200, json: async () => responses.shift() ?? {} }) },
  })
  const panel = new CommanderMainProcessPanel(transport)

  assert.equal((await panel.open()).status, "active")
  assert.equal((await panel.prompt("hello")).status, "active")
  assert.equal((await panel.steer("shorter")).status, "active")
  assert.equal((await panel.cancel()).status, "active")
  assert.deepEqual(actions, ["read", "read", "prompt", "steer", "cancel"])
  assert.equal(JSON.stringify(panel.snapshot()).includes("main-only-proof"), false)
})

test("an unconfigured panel cannot manufacture transport authority", async () => {
  const panel = new CommanderMainProcessPanel(undefined)
  assert.deepEqual(await panel.open(), { status: "not-configured", events: [] })
  assert.deepEqual(await panel.prompt("hello"), { status: "unavailable", events: [] })
})
