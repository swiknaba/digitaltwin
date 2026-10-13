import assert from "node:assert/strict"
import test from "node:test"
import { commandCapabilityBinding, continuationCapabilityBinding } from "./capability-binding.ts"
import { bridgeActorId, bridgeRequestId, commanderConversationId, streamCursor, turnIdForRequest, type CapabilityBinding, type CapabilityDecision, type CapabilityVerifier, type CommanderRuntime, type OpenCodeMessageProvenance } from "./contract.ts"
import { CommanderBridgeController } from "./controller.ts"
import { InMemoryConversationStore } from "./in-memory-store.ts"
import { TrustedOpenCodeContinuation, type OpenCodeSessionClient } from "./opencode-continuation.ts"

const conversation = commanderConversationId("commander:global")
const actor = bridgeActorId("owner")
const now = new Date("2026-10-13T12:00:00.000Z")
const provenance: OpenCodeMessageProvenance = { runtimeId: "runtime-a", projectId: "project-a", sessionId: "ses_child", messageId: "msg_reply", parentSessionId: "ses_parent" }

class Verifier implements CapabilityVerifier {
  private readonly decisions = new Map<string, CapabilityDecision>()

  issue(token: string, action: "read" | "prompt" | "steer" | "cancel" | "continue", binding?: CapabilityBinding, overrides: Partial<Readonly<{ action: "read" | "prompt" | "steer" | "cancel" | "continue"; actorId: typeof actor }>> = {}): Readonly<{ token: string }> {
    this.decisions.set(token, { ok: true, capability: { action: overrides.action ?? action, actorId: overrides.actorId ?? actor, audience: "commander-bridge", conversationId: conversation, issuedAt: new Date("2026-10-13T11:59:00.000Z"), expiresAt: new Date("2026-10-13T12:04:00.000Z"), nonce: token, ...(binding === undefined ? {} : { binding }) } })
    return { token }
  }

  async consume(input: Parameters<CapabilityVerifier["consume"]>[0]): Promise<CapabilityDecision> {
    const decision = this.decisions.get(input.presentation.token) ?? { ok: false, reason: "invalid" as const }
    this.decisions.delete(input.presentation.token)
    return decision
  }
}

class Runtime implements CommanderRuntime {
  async prompt(input: Parameters<CommanderRuntime["prompt"]>[0]) { return { state: "accepted" as const, turnId: input.turnId } }
  async steer(): Promise<void> {}
  async cancel(): Promise<"acknowledged"> { return "acknowledged" }
}

class Client implements OpenCodeSessionClient {
  readonly calls: string[] = []
  sessionState: "found" | "missing" | "inaccessible" = "found"
  messageState: "found" | "missing" | "inaccessible" = "found"
  promptState: "accepted" | "stale" | "missing" | "inaccessible" | "unknown" = "accepted"
  reconcileState: "accepted" | "unknown" = "unknown"

  async session(input: OpenCodeMessageProvenance) { this.calls.push(`session:${input.runtimeId}:${input.projectId}:${input.sessionId}`); return this.sessionState }
  async message(input: OpenCodeMessageProvenance) { this.calls.push(`message:${input.messageId}`); return this.messageState }
  async prompt(input: Readonly<{ provenance: OpenCodeMessageProvenance; text: string; idempotencyKey: string }>) { this.calls.push(`prompt:${input.provenance.sessionId}:${input.text}:${input.idempotencyKey}`); return this.promptState }
  async reconcile(input: Readonly<{ provenance: OpenCodeMessageProvenance; idempotencyKey: string }>) { this.calls.push(`reconcile:${input.provenance.messageId}:${input.idempotencyKey}`); return this.reconcileState }
}

async function subject() {
  const store = new InMemoryConversationStore()
  const verifier = new Verifier()
  const runtime = new Runtime()
  const controller = new CommanderBridgeController({ actorId: actor, conversationId: conversation, store, runtime, verifier, now: () => now })
  const startBinding = commandCapabilityBinding("prompt", "request-start", "hello")
  assert.deepEqual(await controller.prompt(verifier.issue("start", "prompt", startBinding), "request-start", "hello"), { ok: true, state: "dispatched" })
  assert.deepEqual(await controller.apply({ conversationId: conversation, turnId: turnIdForRequest(bridgeRequestId("request-start")), cursor: streamCursor(1), deliveryId: "delivery-1", kind: "delta", text: "working", provenance }), { ok: true, state: "applied" })
  const client = new Client()
  return { store, verifier, runtime, controller, client, service: new TrustedOpenCodeContinuation({ controller, client }) }
}

function continuationProof(verifier: Verifier, token: string, requestId = "continue-1", text = "Follow up", overrides: Parameters<Verifier["issue"]>[3] = {}) {
  return verifier.issue(token, "continue", continuationCapabilityBinding("delivery-1", provenance, requestId, text), overrides)
}

test("continues only the exact persisted child session after controller authorization", async () => {
  const input = await subject()
  assert.deepEqual(await input.service.continue({ presentation: continuationProof(input.verifier, "proof"), deliveryId: "delivery-1", requestId: "continue-1", text: "Follow up" }), { ok: true, state: "continued" })
  assert.deepEqual(input.client.calls, [
    "session:runtime-a:project-a:ses_child",
    "message:msg_reply",
    "prompt:ses_child:Follow up:commander-continue:commander:global:continue-1:eabaa3c0d2576962333a593d27bf75bd1a728644234baf94a5840923abfe91ea",
  ])
})

test("rejects wrong actor, action, or action binding before touching OpenCode", async () => {
  const input = await subject()
  assert.deepEqual(await input.service.continue({ presentation: continuationProof(input.verifier, "wrong-actor", "continue-actor", "Follow up", { actorId: bridgeActorId("other-owner") }), deliveryId: "delivery-1", requestId: "continue-actor", text: "Follow up" }), { ok: false, reason: "unauthorized" })
  assert.deepEqual(await input.service.continue({ presentation: continuationProof(input.verifier, "wrong-action", "continue-action", "Follow up", { action: "read" }), deliveryId: "delivery-1", requestId: "continue-action", text: "Follow up" }), { ok: false, reason: "unauthorized" })
  assert.deepEqual(await input.service.continue({ presentation: input.verifier.issue("wrong-binding", "continue", continuationCapabilityBinding("delivery-1", provenance, "different", "Follow up")), deliveryId: "delivery-1", requestId: "continue-binding", text: "Follow up" }), { ok: false, reason: "unauthorized" })
  assert.deepEqual(input.client.calls, [])
})

test("records a continuation before I/O and never reprompts a fresh-proof duplicate or changed body", async () => {
  const input = await subject()
  const first = { presentation: continuationProof(input.verifier, "first"), deliveryId: "delivery-1", requestId: "continue-1", text: "Follow up" }
  assert.deepEqual(await input.service.continue(first), { ok: true, state: "continued" })
  assert.deepEqual(await input.service.continue({ ...first, presentation: continuationProof(input.verifier, "fresh") }), { ok: true, state: "continued" })
  assert.deepEqual(await input.service.continue({ presentation: continuationProof(input.verifier, "changed", "continue-1", "Altered"), deliveryId: "delivery-1", requestId: "continue-1", text: "Altered" }), { ok: false, reason: "request_conflict" })
  assert.equal(input.client.calls.filter((call) => call.startsWith("prompt:")).length, 1)
})

test("never replaces a missing message after a found session", async () => {
  const input = await subject()
  input.client.messageState = "missing"
  assert.deepEqual(await input.service.continue({ presentation: continuationProof(input.verifier, "proof"), deliveryId: "delivery-1", requestId: "continue-1", text: "Follow up" }), { ok: false, reason: "missing" })
  assert.deepEqual(input.client.calls, ["session:runtime-a:project-a:ses_child", "message:msg_reply"])
})

test("reconciles an unknown post-prompt outcome and remains no-retry after restart", async () => {
  const input = await subject()
  input.client.promptState = "unknown"
  input.client.reconcileState = "unknown"
  assert.deepEqual(await input.service.continue({ presentation: continuationProof(input.verifier, "first"), deliveryId: "delivery-1", requestId: "continue-1", text: "Follow up" }), { ok: false, reason: "uncertain" })
  const restarted = new CommanderBridgeController({ actorId: actor, conversationId: conversation, store: input.store, runtime: input.runtime, verifier: input.verifier, now: () => now })
  const resumed = new TrustedOpenCodeContinuation({ controller: restarted, client: input.client })
  assert.deepEqual(await resumed.continue({ presentation: continuationProof(input.verifier, "fresh"), deliveryId: "delivery-1", requestId: "continue-1", text: "Follow up" }), { ok: false, reason: "uncertain" })
  assert.equal(input.client.calls.filter((call) => call.startsWith("prompt:")).length, 1)
  assert.equal(input.client.calls.filter((call) => call.startsWith("reconcile:")).length, 1)
})
