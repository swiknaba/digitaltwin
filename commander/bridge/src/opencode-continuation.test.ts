import assert from "node:assert/strict"
import test from "node:test"
import { commandCapabilityBinding } from "./capability-binding.ts"
import { bridgeActorId, bridgeRequestId, commanderConversationId, streamCursor, turnIdForRequest, type CapabilityBinding, type CapabilityDecision, type CapabilityVerifier, type CommanderRuntime, type OpenCodeMessageProvenance } from "./contract.ts"
import { CommanderBridgeController } from "./controller.ts"
import { InMemoryConversationStore } from "./in-memory-store.ts"
import { OpenCodeHttpSessionClient, OpenCodeSessionContinuation, type OpenCodeSessionClient } from "./opencode-continuation.ts"

const conversation = commanderConversationId("commander:global")
const actor = bridgeActorId("owner")
const now = new Date("2026-10-14T12:00:00.000Z")
const provenance: OpenCodeMessageProvenance = { runtimeId: "opencode:developer", projectId: "project-a", sessionId: "ses_child", messageId: "msg_reply", parentSessionId: "ses_parent" }

class Verifier implements CapabilityVerifier {
  private readonly decisions = new Map<string, CapabilityDecision>()

  issue(token: string, action: "read" | "prompt" | "steer" | "cancel", binding?: CapabilityBinding): Readonly<{ token: string }> {
    this.decisions.set(token, { ok: true, capability: { action, actorId: actor, audience: "commander-bridge", conversationId: conversation, issuedAt: new Date("2026-10-14T11:59:00.000Z"), expiresAt: new Date("2026-10-14T12:04:00.000Z"), nonce: token, ...(binding === undefined ? {} : { binding }) } })
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
  readonly calls: Array<Readonly<{ kind: "session" | "message" | "prompt"; input: OpenCodeMessageProvenance | Readonly<{ provenance: OpenCodeMessageProvenance; inputId: string; text: string; metadata: Readonly<{ fromCommander: true }> }> }>> = []
  sessionState: "found" | "missing" | "inaccessible" = "found"
  messageState: "found" | "missing" | "inaccessible" = "found"
  promptState: "accepted" | "stale" | "missing" | "inaccessible" | "unknown" = "accepted"

  async session(input: OpenCodeMessageProvenance) { this.calls.push({ kind: "session", input }); return this.sessionState }
  async message(input: OpenCodeMessageProvenance) { this.calls.push({ kind: "message", input }); return this.messageState }
  async prompt(input: Readonly<{ provenance: OpenCodeMessageProvenance; inputId: string; text: string; metadata: Readonly<{ fromCommander: true }> }>) { this.calls.push({ kind: "prompt", input }); return this.promptState }
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
  return { store, verifier, runtime, controller, client, service: new OpenCodeSessionContinuation({ controller, client }) }
}

const continuation = { deliveryId: "delivery-1", requestId: "continue-1", text: "Follow up" }

test("routes Commander provenance to exactly one ordinary OpenCode input", async () => {
  const input = await subject()
  assert.deepEqual(await input.service.continue(continuation), { ok: true, state: "continued" })
  assert.deepEqual(input.client.calls.slice(0, 2), [{ kind: "session", input: provenance }, { kind: "message", input: provenance }])
  assert.deepEqual(input.client.calls[2], {
    kind: "prompt",
    input: {
      provenance,
      inputId: "msg_commander_e4910a820e50df03d2a2b3b8a9a78e6d7d9b083f26a56ce512b47c63756121c3",
      text: "Follow up",
      metadata: { fromCommander: true },
    },
  })
})

test("does not duplicate an admitted input or accept a changed body", async () => {
  const input = await subject()
  assert.deepEqual(await input.service.continue(continuation), { ok: true, state: "continued" })
  assert.deepEqual(await input.service.continue(continuation), { ok: true, state: "continued" })
  assert.deepEqual(await input.service.continue({ ...continuation, text: "Altered" }), { ok: false, reason: "request_conflict" })
  assert.equal(input.client.calls.filter((call) => call.kind === "prompt").length, 1)
})

test("rejects a missing exact source message without selecting a replacement", async () => {
  const input = await subject()
  input.client.messageState = "missing"
  assert.deepEqual(await input.service.continue(continuation), { ok: false, reason: "missing" })
  assert.deepEqual(input.client.calls.map((call) => call.kind), ["session", "message"])
})

test("retries an uncertain standard OpenCode input with the same ID after restart", async () => {
  const input = await subject()
  input.client.promptState = "unknown"
  assert.deepEqual(await input.service.continue(continuation), { ok: false, reason: "uncertain" })
  input.client.promptState = "accepted"
  const restarted = new CommanderBridgeController({ actorId: actor, conversationId: conversation, store: input.store, runtime: input.runtime, verifier: input.verifier, now: () => now })
  const resumed = new OpenCodeSessionContinuation({ controller: restarted, client: input.client })
  assert.deepEqual(await resumed.continue(continuation), { ok: true, state: "continued" })
  const prompts = input.client.calls.filter((call) => call.kind === "prompt")
  assert.equal(prompts.length, 2)
  assert.equal((prompts[0]!.input as Readonly<{ inputId: string }>).inputId, (prompts[1]!.input as Readonly<{ inputId: string }>).inputId)
})

test("retries a persisted pre-dispatch input after process death with the same standard ID", async () => {
  const input = await subject()
  const prepared = await input.controller.prepareContinuation(continuation.deliveryId, continuation.requestId, continuation.text)
  assert.equal(prepared.ok, true)
  if (!prepared.ok) return
  const restarted = new CommanderBridgeController({ actorId: actor, conversationId: conversation, store: input.store, runtime: input.runtime, verifier: input.verifier, now: () => now })
  const resumed = new OpenCodeSessionContinuation({ controller: restarted, client: input.client })
  assert.deepEqual(await resumed.continue(continuation), { ok: true, state: "continued" })
  const prompt = input.client.calls.find((call) => call.kind === "prompt")?.input as Readonly<{ inputId: string }>
  assert.equal(prompt.inputId, prepared.inputId)
})

test("uses the pinned ordinary OpenCode endpoint and carries only Commander provenance metadata", async () => {
  const requests: Array<Readonly<{ url: string; method?: string; body?: string }>> = []
  const client = new OpenCodeHttpSessionClient({
    origin: "https://opencode.example.test/ignored-path",
    runtimeId: "opencode:developer",
    fetch: { async fetch(url, init) { requests.push({ url, ...(init?.method === undefined ? {} : { method: init.method }), ...(init?.body === undefined ? {} : { body: init.body }) }); return { status: 200 } } },
  })
  assert.equal(await client.session(provenance), "found")
  assert.equal(await client.message(provenance), "found")
  assert.equal(await client.prompt({ provenance, inputId: "msg_commander_test", text: "Follow up", metadata: { fromCommander: true } }), "accepted")
  assert.deepEqual(requests, [
    { url: "https://opencode.example.test/api/session/ses_child" },
    { url: "https://opencode.example.test/api/session/ses_child/message/msg_reply" },
    { url: "https://opencode.example.test/api/session/ses_child/prompt", method: "POST", body: "{\"id\":\"msg_commander_test\",\"text\":\"Follow up\",\"metadata\":{\"fromCommander\":true},\"resume\":true}" },
  ])
})
