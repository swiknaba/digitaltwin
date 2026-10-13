import assert from "node:assert/strict"
import test from "node:test"
import { bridgeActorId, commanderConversationId, streamCursor, type CapabilityDecision, type CapabilityVerifier, type CommanderRuntime } from "./contract.ts"
import { CommanderBridgeController } from "./controller.ts"
import { InMemoryConversationStore } from "./in-memory-store.ts"

const conversation = commanderConversationId("commander:global")
const actor = bridgeActorId("owner-1")
const now = new Date("2026-10-13T12:00:00.000Z")
class Verifier implements CapabilityVerifier {
  readonly used = new Set<string>(); readonly decisions = new Map<string, CapabilityDecision>()
  issue(token: string, action: "read" | "prompt" | "steer" | "cancel", override: Partial<{ action: "read" | "prompt" | "steer" | "cancel"; expiresAt: Date }> = {}) { this.decisions.set(token, { ok: true, capability: { action: override.action ?? action, actorId: actor, audience: "commander-bridge", conversationId: conversation, issuedAt: new Date("2026-10-13T11:59:00.000Z"), expiresAt: override.expiresAt ?? new Date("2026-10-13T12:04:00.000Z"), nonce: token } }); return { token } }
  async consume(input: Parameters<CapabilityVerifier["consume"]>[0]): Promise<CapabilityDecision> { if (this.used.has(input.presentation.token)) return { ok: false, reason: "replayed" }; const result = this.decisions.get(input.presentation.token) ?? { ok: false, reason: "invalid" }; if (result.ok) this.used.add(input.presentation.token); return result }
}
class Runtime implements CommanderRuntime { prompts: string[] = []; async prompt(input: Parameters<CommanderRuntime["prompt"]>[0]) { this.prompts.push(input.requestId) }; async steer(_input: Parameters<CommanderRuntime["steer"]>[0]) {}; async cancel(_input: Parameters<CommanderRuntime["cancel"]>[0]) { return "acknowledged" as const } }
function subject() { const store = new InMemoryConversationStore(); const runtime = new Runtime(); const verifier = new Verifier(); return { store, runtime, verifier, controller: new CommanderBridgeController({ actorId: actor, conversationId: conversation, store, runtime, verifier, now: () => now }) } }

test("reconnect replays persisted events from the caller cursor", async () => {
  const input = subject()
  await input.controller.apply({ conversationId: conversation, cursor: streamCursor(1), deliveryId: "one", kind: "delta", text: "one" })
  await input.controller.apply({ conversationId: conversation, cursor: streamCursor(2), deliveryId: "two", kind: "final", text: "two", outcome: "completed" })
  const result = await input.controller.reconnect(input.verifier.issue("read", "read"), 0)
  assert.equal(result.ok, true); if (result.ok) assert.deepEqual(result.events.map((event) => event.deliveryId), ["one", "two"])
})
test("capabilities are action-, expiry-, and replay-bound", async () => {
  const input = subject()
  assert.deepEqual(await input.controller.prompt(input.verifier.issue("wrong", "prompt", { action: "read" }), "request-1", "hello"), { ok: false, reason: "action_mismatch" })
  assert.deepEqual(await input.controller.cancel(input.verifier.issue("expired", "cancel", { expiresAt: new Date("2026-10-13T11:59:59.000Z") }), "request-2"), { ok: false, reason: "expired" })
  const once = input.verifier.issue("once", "prompt"); assert.deepEqual(await input.controller.prompt(once, "request-3", "hello"), { ok: true, state: "dispatched" }); assert.deepEqual(await input.controller.prompt(once, "request-4", "again"), { ok: false, reason: "replayed" })
})
test("records a request before dispatch and never repeats it", async () => {
  const input = subject(); assert.deepEqual(await input.controller.prompt(input.verifier.issue("prompt", "prompt"), "request-1", "hello"), { ok: true, state: "dispatched" }); assert.deepEqual(await input.controller.prompt(input.verifier.issue("retry", "prompt"), "request-1", "hello"), { ok: true, state: "already_recorded" }); assert.deepEqual(input.runtime.prompts, ["request-1"])
})
test("does not overwrite a terminal stream state with cancellation", async () => {
  const input = subject(); await input.controller.apply({ conversationId: conversation, cursor: streamCursor(1), deliveryId: "done", kind: "final", text: "done", outcome: "completed" }); assert.deepEqual(await input.controller.cancel(input.verifier.issue("cancel", "cancel"), "request-1"), { ok: false, reason: "terminal" }); assert.equal((await input.store.load(conversation))?.status, "completed")
})
