import assert from "node:assert/strict"
import { mkdtemp, rm, stat } from "node:fs/promises"
import { request } from "node:http"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test from "node:test"
import { commandCapabilityBinding } from "./capability-binding.ts"
import { bridgeActorId, bridgeRequestId, commanderConversationId, streamCursor, turnIdForRequest, type CommanderRuntime } from "./contract.ts"
import { CommanderBridgeController } from "./controller.ts"
import { EphemeralTestAuthority } from "./ephemeral-test-authority.ts"
import { InMemoryConversationStore } from "./in-memory-store.ts"
import { createRuntimeEventNodeListener, listenRuntimeEventSocket } from "./runtime-event-node-listener.ts"
import { RuntimeEventIngress } from "./runtime-event-ingress.ts"

const actor = bridgeActorId("owner-1")
const conversation = commanderConversationId("commander:global")
const now = new Date("2026-10-13T12:00:00.000Z")

class Runtime implements CommanderRuntime {
  async prompt(input: Parameters<CommanderRuntime["prompt"]>[0]) { return { state: "accepted" as const, turnId: input.turnId } }
  async steer(_input: Parameters<CommanderRuntime["steer"]>[0]): Promise<void> {}
  async cancel(_input: Parameters<CommanderRuntime["cancel"]>[0]) { return "acknowledged" as const }
}

test("runtime ingress is reachable only through a private mode-0600 socket and separate proof", async () => {
  const directory = await mkdtemp(join(tmpdir(), "digitaltwin-commander-runtime-"))
  const socket = join(directory, "runtime.sock")
  const authority = new EphemeralTestAuthority({ actorId: actor, conversationId: conversation, now: () => now })
  const controller = new CommanderBridgeController({ actorId: actor, conversationId: conversation, runtime: new Runtime(), store: new InMemoryConversationStore(), verifier: authority, now: () => now })
  await controller.prompt(await authority.issue({ action: "prompt", binding: commandCapabilityBinding("prompt", "request-start", "hello") }), "request-start", "hello")
  const ingress = new RuntimeEventIngress({ controller, conversationId: conversation, authenticator: authority, now: () => now })
  const server = createRuntimeEventNodeListener(ingress)

  try {
    await listenRuntimeEventSocket(server, socket)
    assert.equal((await stat(socket)).mode & 0o777, 0o600)
    const body = { conversationId: conversation, turnId: turnIdForRequest(bridgeRequestId("request-start")), cursor: streamCursor(1), deliveryId: "event-1", kind: "delta", text: "working" }
    assert.deepEqual(await post(socket, authority.issueRuntimeEventProof().token, body), { status: 200, body: { ok: true, state: "applied" } })
    assert.deepEqual(await post(socket, "panel-proof", body), { status: 401, body: { ok: false, reason: "unauthenticated" } })
  } finally {
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()))
    await rm(directory, { recursive: true, force: true })
  }
})

function post(socketPath: string, token: string, body: unknown): Promise<{ status: number; body: unknown }> {
  return new Promise((resolve, reject) => {
    const caller = request({ socketPath, path: "/v1/commander/runtime-events", method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" } }, (response) => {
      let text = ""; response.setEncoding("utf8"); response.on("data", (chunk: string) => { text += chunk }); response.on("end", () => resolve({ status: response.statusCode ?? 0, body: JSON.parse(text) as unknown }))
    })
    caller.on("error", reject); caller.end(JSON.stringify(body))
  })
}
