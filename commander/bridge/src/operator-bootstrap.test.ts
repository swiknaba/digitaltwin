import assert from "node:assert/strict"
import test from "node:test"
import { commandCapabilityBinding } from "./capability-binding.ts"
import { bridgeActorId, commanderConversationId } from "./contract.ts"
import { createOperatorHostBootstrap, OperatorMainProcessCapabilityIssuer } from "./operator-bootstrap.ts"

test("operator bootstrap supplies identity while the main process supplies the command binding", async () => {
  const issued: unknown[] = []
  const issuer = new OperatorMainProcessCapabilityIssuer({
    identity: { actorId: bridgeActorId("owner-1"), conversationId: commanderConversationId("commander:global") },
    exchange: { issue: async (input) => { issued.push(input); return { token: "ephemeral-proof" } } },
  })
  const binding = commandCapabilityBinding("prompt", "request-1", "hello")
  assert.deepEqual(await issuer.issue({ action: "prompt", binding }), { token: "ephemeral-proof" })
  assert.deepEqual(issued, [{ audience: "commander-bridge", actorId: bridgeActorId("owner-1"), conversationId: commanderConversationId("commander:global"), action: "prompt", binding }])
})

test("operator deployment adapter creates a main-process-only panel", () => {
  const bootstrap = createOperatorHostBootstrap({
    bridgeOrigin: "http://127.0.0.1:4312",
    identity: { actorId: bridgeActorId("owner-1"), conversationId: commanderConversationId("commander:global") },
    exchange: { issue: async () => ({ token: "ephemeral-proof" }) },
    fetch: { fetch: async () => ({ status: 500, json: async () => ({}) }) },
  })
  assert.deepEqual(bootstrap.createPanel().snapshot(), { status: "not-configured", events: [] })
})
