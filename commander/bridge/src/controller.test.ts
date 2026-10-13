import assert from "node:assert/strict"
import test from "node:test"
import { bridgeActorId, bridgeRequestId, commanderConversationId, streamCursor, turnIdForRequest, type CapabilityDecision, type CapabilityVerifier, type CommanderRuntime } from "./contract.ts"
import { CommanderBridgeController } from "./controller.ts"
import { InMemoryConversationStore } from "./in-memory-store.ts"

const conversation = commanderConversationId("commander:global")
const actor = bridgeActorId("owner-1")
const now = new Date("2026-10-13T12:00:00.000Z")

class Verifier implements CapabilityVerifier {
  readonly used = new Set<string>(); readonly decisions = new Map<string, CapabilityDecision>()
  issue(token: string, action: "read" | "prompt" | "steer" | "cancel", override: Partial<{ action: "read" | "prompt" | "steer" | "cancel"; actorId: typeof actor; expiresAt: Date; issuedAt: Date }> = {}) {
    this.decisions.set(token, { ok: true, capability: { action: override.action ?? action, actorId: override.actorId ?? actor, audience: "commander-bridge", conversationId: conversation, issuedAt: override.issuedAt ?? new Date("2026-10-13T11:59:00.000Z"), expiresAt: override.expiresAt ?? new Date("2026-10-13T12:04:00.000Z"), nonce: token } })
    return { token }
  }
  async consume(input: Parameters<CapabilityVerifier["consume"]>[0]): Promise<CapabilityDecision> {
    if (this.used.has(input.presentation.token)) return { ok: false, reason: "replayed" }
    const result = this.decisions.get(input.presentation.token) ?? { ok: false, reason: "invalid" }
    if (!result.ok) return result
    this.used.add(input.presentation.token)
    return { ok: true, capability: { ...result.capability, ...(result.capability.binding === undefined && input.expectedBinding !== undefined ? { binding: input.expectedBinding } : {}) } }
  }
}

class Runtime implements CommanderRuntime {
  prompts: string[] = []; steers: string[] = []; cancels: string[] = []; failPrompt = false
  private resolveEntered: (() => void) | undefined
  private resolvePrompt: (() => void) | undefined
  private readonly promptEntered = new Promise<void>((resolve) => { this.resolveEntered = resolve })
  private readonly promptReleased = new Promise<void>((resolve) => { this.resolvePrompt = resolve })
  holdPrompt = false
  async waitForPrompt(): Promise<void> { await this.promptEntered }
  releasePrompt(): void { this.resolvePrompt?.() }
  async prompt(input: Parameters<CommanderRuntime["prompt"]>[0]) { this.prompts.push(input.requestId); this.resolveEntered?.(); if (this.holdPrompt) await this.promptReleased; if (this.failPrompt) throw new Error("runtime unavailable"); return { state: "accepted" as const, turnId: input.turnId } }
  async steer(input: Parameters<CommanderRuntime["steer"]>[0]) { this.steers.push(input.turnId) }
  async cancel(input: Parameters<CommanderRuntime["cancel"]>[0]) { this.cancels.push(input.turnId); return "acknowledged" as const }
}

function subject() { const store = new InMemoryConversationStore(); const runtime = new Runtime(); const verifier = new Verifier(); return { store, runtime, verifier, controller: new CommanderBridgeController({ actorId: actor, conversationId: conversation, store, runtime, verifier, now: () => now }) } }
function runtimeEvent(requestId: string, cursor: number, kind: "delta" | "final" = "delta") {
  const turnId = turnIdForRequest(bridgeRequestId(requestId))
  return kind === "final"
    ? { conversationId: conversation, turnId, cursor: streamCursor(cursor), deliveryId: `event-${cursor}`, kind, text: "done", outcome: "completed" as const }
    : { conversationId: conversation, turnId, cursor: streamCursor(cursor), deliveryId: `event-${cursor}`, kind, text: "working" }
}

test("reconnect replays persisted events from the caller cursor", async () => {
  const input = subject()
  await input.controller.prompt(input.verifier.issue("start", "prompt"), "request-start", "hello")
  await input.controller.apply(runtimeEvent("request-start", 1))
  await input.controller.apply(runtimeEvent("request-start", 2, "final"))
  const result = await input.controller.reconnect(input.verifier.issue("read", "read"), 0)
  assert.equal(result.ok, true); if (result.ok) assert.deepEqual(result.events.map((item) => item.deliveryId), ["event-1", "event-2"])
})

test("capabilities are action-, expiry-, body-, and replay-bound", async () => {
  const input = subject()
  assert.deepEqual(await input.controller.prompt(input.verifier.issue("wrong", "prompt", { action: "read" }), "request-1", "hello"), { ok: false, reason: "action_mismatch" })
  assert.deepEqual(await input.controller.cancel(input.verifier.issue("expired", "cancel", { expiresAt: new Date("2026-10-13T11:59:59.000Z") }), "request-2"), { ok: false, reason: "expired" })
  const once = input.verifier.issue("once", "prompt")
  assert.deepEqual(await input.controller.prompt(once, "request-3", "hello"), { ok: true, state: "dispatched" })
  assert.deepEqual(await input.controller.prompt(once, "request-4", "again"), { ok: false, reason: "replayed" })
  assert.deepEqual(await input.controller.prompt(input.verifier.issue("substitute", "prompt"), "request-3", "altered"), { ok: false, reason: "request_conflict" })
})

test("capabilities reject a different actor, invalid issue time, and excessive lifetime", async () => {
  const input = subject()
  assert.deepEqual(await input.controller.open(input.verifier.issue("other-actor", "read", { actorId: bridgeActorId("other-owner") })), { ok: false, reason: "actor_mismatch" })
  assert.deepEqual(await input.controller.open(input.verifier.issue("bad-time", "read", { issuedAt: new Date("invalid") })), { ok: false, reason: "expired" })
  assert.deepEqual(await input.controller.open(input.verifier.issue("long", "read", { issuedAt: new Date("2026-10-13T11:00:00.000Z"), expiresAt: new Date("2026-10-13T13:00:00.000Z") })), { ok: false, reason: "expired" })
})

test("slow runtime prompt does not block a concurrent cancel and duplicate action does not redispatch", async () => {
  const input = subject(); input.runtime.holdPrompt = true
  const prompt = input.controller.prompt(input.verifier.issue("prompt", "prompt"), "request-start", "hello")
  await input.runtime.waitForPrompt()
  assert.deepEqual(await input.controller.prompt(input.verifier.issue("duplicate", "prompt"), "request-start", "hello"), { ok: true, state: "already_recorded" })
  assert.deepEqual(await input.controller.cancel(input.verifier.issue("cancel", "cancel"), "request-cancel"), { ok: true, state: "dispatched" })
  assert.deepEqual(input.runtime.cancels, [turnIdForRequest(bridgeRequestId("request-start"))])
  input.runtime.releasePrompt()
  assert.deepEqual(await prompt, { ok: true, state: "dispatched" })
  assert.equal((await input.store.load(conversation))?.status, "cancel_requested")
  assert.deepEqual(input.runtime.prompts, ["request-start"])
})

test("final event clears the active turn and rejects late events from the old turn", async () => {
  const input = subject()
  await input.controller.prompt(input.verifier.issue("start", "prompt"), "request-start", "hello")
  assert.deepEqual(await input.controller.apply(runtimeEvent("request-start", 1, "final")), { ok: true, state: "applied" })
  assert.deepEqual(await input.controller.prompt(input.verifier.issue("next", "prompt"), "request-next", "again"), { ok: true, state: "dispatched" })
  assert.deepEqual(await input.controller.apply(runtimeEvent("request-start", 2)), { ok: false, reason: "stale_turn" })
  assert.equal((await input.store.load(conversation))?.activeTurn?.id, turnIdForRequest(bridgeRequestId("request-next")))
})

test("failed runtime request remains uncertain across a controller restart", async () => {
  const input = subject(); input.runtime.failPrompt = true
  assert.deepEqual(await input.controller.prompt(input.verifier.issue("fail", "prompt"), "request-start", "hello"), { ok: false, reason: "uncertain" })
  const restarted = new CommanderBridgeController({ actorId: actor, conversationId: conversation, store: input.store, runtime: input.runtime, verifier: input.verifier, now: () => now })
  assert.deepEqual(await restarted.prompt(input.verifier.issue("retry", "prompt"), "request-start", "hello"), { ok: false, reason: "uncertain" })
})

test("persists exact optional OpenCode provenance without treating it as authority", async () => {
  const input = subject()
  await input.controller.prompt(input.verifier.issue("start", "prompt"), "request-start", "hello")
  const event = {
    ...runtimeEvent("request-start", 1),
    provenance: { runtimeId: "desktop:operator-a", projectId: "project-a", sessionId: "ses_child", messageId: "msg_reply", agentId: "reviewer", parentSessionId: "ses_parent" },
  }
  assert.deepEqual(await input.controller.apply(event), { ok: true, state: "applied" })
  const restarted = new CommanderBridgeController({ actorId: actor, conversationId: conversation, store: input.store, runtime: input.runtime, verifier: input.verifier, now: () => now })
  assert.deepEqual(await restarted.provenanceForDelivery("event-1"), event.provenance)
  assert.equal(await restarted.provenanceForDelivery("missing"), undefined)
})
