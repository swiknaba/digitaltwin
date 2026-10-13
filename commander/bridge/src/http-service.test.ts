import assert from "node:assert/strict"
import { createServer } from "node:http"
import test from "node:test"
import { bridgeActorId, commanderConversationId, type CapabilityDecision, type CapabilityVerifier, type CommanderRuntime } from "./contract.ts"
import { CommanderBridgeController } from "./controller.ts"
import { CommanderBridgeHttpService } from "./http-service.ts"
import { InMemoryConversationStore } from "./in-memory-store.ts"

const actor = bridgeActorId("owner-1")
const conversation = commanderConversationId("commander:global")
const now = new Date("2026-10-13T12:00:00.000Z")

class Verifier implements CapabilityVerifier {
  readonly used = new Set<string>()
  async consume(input: Parameters<CapabilityVerifier["consume"]>[0]): Promise<CapabilityDecision> {
    if (input.presentation.token !== "ephemeral-prompt" || this.used.has(input.presentation.token)) return { ok: false, reason: "replayed" }
    this.used.add(input.presentation.token)
    return { ok: true, capability: { action: "prompt", actorId: actor, audience: "commander-bridge", conversationId: conversation, issuedAt: new Date("2026-10-13T11:59:00.000Z"), expiresAt: new Date("2026-10-13T12:04:00.000Z"), nonce: input.presentation.token } }
  }
}

class Runtime implements CommanderRuntime {
  prompts: string[] = []
  async prompt(input: Parameters<CommanderRuntime["prompt"]>[0]) { this.prompts.push(input.text) }
  async steer(_input: Parameters<CommanderRuntime["steer"]>[0]) {}
  async cancel(_input: Parameters<CommanderRuntime["cancel"]>[0]) { return "acknowledged" as const }
}

test("loopback transport binds an ephemeral proof in a header and never echoes it", async () => {
  const runtime = new Runtime()
  const controller = new CommanderBridgeController({ actorId: actor, conversationId: conversation, runtime, store: new InMemoryConversationStore(), verifier: new Verifier(), now: () => now })
  const service = new CommanderBridgeHttpService(controller)
  const server = createServer(async (request, response) => {
    const chunks: Buffer[] = []
    for await (const chunk of request) chunks.push(Buffer.from(chunk))
    const body: unknown = chunks.length === 0 ? {} : JSON.parse(Buffer.concat(chunks).toString("utf8"))
    const authorization = request.headers.authorization
    const input = authorization === undefined
      ? { method: "POST" as const, path: request.url as "/v1/commander/prompt", body }
      : { method: "POST" as const, path: request.url as "/v1/commander/prompt", authorization, body }
    const result = await service.handle(input)
    response.writeHead(result.status, { "content-type": "application/json" })
    response.end(JSON.stringify(result.body))
  })
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve))
  const address = server.address()
  if (!address || typeof address === "string") throw new Error("Missing loopback address")
  try {
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/commander/prompt`, { method: "POST", headers: { authorization: "Bearer ephemeral-prompt", "content-type": "application/json" }, body: JSON.stringify({ requestId: "request-1", text: "hello" }) })
    const body = await response.text()
    assert.equal(response.status, 200)
    assert.equal(body.includes("ephemeral-prompt"), false)
    assert.deepEqual(JSON.parse(body), { ok: true, state: "dispatched" })
    assert.deepEqual(runtime.prompts, ["hello"])
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()))
  }
})
