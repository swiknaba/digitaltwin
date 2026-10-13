import assert from "node:assert/strict"
import test from "node:test"
import { bridgeActorId, commanderConversationId, type CapabilityVerifier } from "./contract.ts"
import { TrustedOpenCodeContinuation } from "./opencode-continuation.ts"

const conversation = commanderConversationId("commander:global")
const provenance = { runtimeId: "runtime-a", projectId: "project-a", sessionId: "ses_child", messageId: "msg_reply", parentSessionId: "ses_parent" }

function subject(state: "found" | "missing" | "inaccessible" = "found") {
  const calls: string[] = []
  const verifier: CapabilityVerifier = { async consume() { return { ok: true, capability: { action: "continue", actorId: bridgeActorId("owner"), audience: "commander-bridge", conversationId: conversation, issuedAt: new Date(0), expiresAt: new Date(1), nonce: "test" } } } }
  const controller = { async provenanceForDelivery(id: string) { return id === "delivery-1" ? provenance : undefined } }
  const client = {
    async session(input: typeof provenance) { calls.push(`session:${input.runtimeId}:${input.projectId}:${input.sessionId}`); return state },
    async message(input: typeof provenance) { calls.push(`message:${input.messageId}`); return state },
    async prompt(input: { provenance: typeof provenance; text: string }) { calls.push(`prompt:${input.provenance.sessionId}:${input.text}`); return "accepted" as const },
  }
  return { calls, service: new TrustedOpenCodeContinuation({ controller: controller as never, verifier, conversationId: conversation, client, now: () => new Date(0) }) }
}

test("continues only the exact persisted child session after one-use authorization", async () => {
  const input = subject()
  assert.deepEqual(await input.service.continue({ presentation: { token: "proof" }, deliveryId: "delivery-1", requestId: "request-1", text: "Follow up" }), { ok: true, state: "continued" })
  assert.deepEqual(input.calls, ["session:runtime-a:project-a:ses_child", "message:msg_reply", "prompt:ses_child:Follow up"])
})

test("never replaces missing or inaccessible targets", async () => {
  for (const state of ["missing", "inaccessible"] as const) {
    const input = subject(state)
    assert.deepEqual(await input.service.continue({ presentation: { token: "proof" }, deliveryId: "delivery-1", requestId: "request-1", text: "Follow up" }), { ok: false, reason: state })
    assert.equal(input.calls.some((call) => call.startsWith("prompt:")), false)
  }
})
