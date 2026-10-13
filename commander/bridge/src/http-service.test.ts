import assert from "node:assert/strict"
import test from "node:test"
import { commandCapabilityBinding } from "./capability-binding.ts"
import { bridgeActorId, commanderConversationId, streamCursor, type CommanderRuntime } from "./contract.ts"
import { CommanderBridgeController } from "./controller.ts"
import { EphemeralTestAuthority } from "./ephemeral-test-authority.ts"
import { CommanderBridgeHttpService } from "./http-service.ts"
import { InMemoryConversationStore } from "./in-memory-store.ts"
import { CommanderMainProcessTransport } from "./main-process-transport.ts"
import { createCommanderBridgeNodeListener } from "./node-http-listener.ts"
import { RuntimeEventIngress } from "./runtime-event-ingress.ts"

const actor = bridgeActorId("owner-1")
const conversation = commanderConversationId("commander:global")
const now = new Date("2026-10-13T12:00:00.000Z")

class Runtime implements CommanderRuntime {
  prompts: string[] = []
  async prompt(input: Parameters<CommanderRuntime["prompt"]>[0]): Promise<void> { this.prompts.push(input.text) }
  async steer(_input: Parameters<CommanderRuntime["steer"]>[0]): Promise<void> {}
  async cancel(_input: Parameters<CommanderRuntime["cancel"]>[0]): Promise<"acknowledged" | "already_terminal"> { return "acknowledged" }
}

test("local desktop transport uses one bound ephemeral proof through the private listener", async () => {
  const runtime = new Runtime()
  const authority = new EphemeralTestAuthority({ actorId: actor, conversationId: conversation, now: () => now })
  const controller = new CommanderBridgeController({ actorId: actor, conversationId: conversation, runtime, store: new InMemoryConversationStore(), verifier: authority, now: () => now })
  const server = createCommanderBridgeNodeListener(new CommanderBridgeHttpService(controller))
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve))
  const address = server.address()
  if (!address || typeof address === "string") throw new Error("Missing loopback address")
  try {
    const transport = new CommanderMainProcessTransport({ baseUrl: `http://127.0.0.1:${address.port}`, capabilityIssuer: authority, fetch: { fetch } })
    assert.deepEqual(await transport.prompt("request-1", "hello"), { ok: true, state: "dispatched" })
    assert.deepEqual(runtime.prompts, ["hello"])
    assert.deepEqual(await transport.prompt("request-1", "altered"), { ok: false, reason: "request_conflict" })
    const proof = await authority.issue({ action: "prompt", binding: commandCapabilityBinding("prompt", "request-2", "original") })
    const substituted = await fetch(`http://127.0.0.1:${address.port}/v1/commander/prompt`, { method: "POST", headers: { authorization: `Bearer ${proof.token}`, "content-type": "application/json" }, body: JSON.stringify({ requestId: "request-2", text: "altered" }) })
    const unknown = await fetch(`http://127.0.0.1:${address.port}/v1/commander/event`, { method: "POST", headers: { "content-type": "application/json" }, body: "{}" })
    const wrongMethod = await fetch(`http://127.0.0.1:${address.port}/v1/commander/open`, { method: "GET" })
    assert.equal(unknown.status, 404)
    assert.equal(wrongMethod.status, 405)
    assert.equal(substituted.status, 200)
    assert.deepEqual(await substituted.json(), { ok: false, reason: "invalid" })
  } finally { await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve())) }
})

test("runtime events require their separate ephemeral runtime proof", async () => {
  const authority = new EphemeralTestAuthority({ actorId: actor, conversationId: conversation, now: () => now })
  const controller = new CommanderBridgeController({ actorId: actor, conversationId: conversation, runtime: new Runtime(), store: new InMemoryConversationStore(), verifier: authority, now: () => now })
  const ingress = new RuntimeEventIngress({ controller, conversationId: conversation, authenticator: authority, now: () => now })
  const binding = commandCapabilityBinding("prompt", "request-start", "hello")
  await controller.prompt(await authority.issue({ action: "prompt", binding }), "request-start", "hello")
  const event = { conversationId: conversation, cursor: streamCursor(1), deliveryId: "event-1", kind: "delta" as const, text: "working" }
  assert.deepEqual(await ingress.deliver({ token: "not-a-runtime-proof" }, event), { ok: false, reason: "unauthenticated" })
  assert.deepEqual(await ingress.deliver(authority.issueRuntimeEventProof(), event), { ok: true, state: "applied" })
})
