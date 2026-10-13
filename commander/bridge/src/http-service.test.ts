import assert from "node:assert/strict"
import { execFile } from "node:child_process"
import { promisify } from "node:util"
import test from "node:test"
import { commandCapabilityBinding } from "./capability-binding.ts"
import { bridgeActorId, bridgeRequestId, commanderConversationId, streamCursor, turnIdForRequest, type CommanderRuntime } from "./contract.ts"
import { CommanderBridgeController } from "./controller.ts"
import { EphemeralTestAuthority } from "./ephemeral-test-authority.ts"
import { InMemoryFutureTaskDeliveryStore } from "./future-task-delivery.ts"
import { CommanderBridgeHttpService } from "./http-service.ts"
import { InMemoryConversationStore } from "./in-memory-store.ts"
import { CommanderMainProcessTransport } from "./main-process-transport.ts"
import { createCommanderBridgeNodeListener } from "./node-http-listener.ts"
import { RuntimeEventIngress } from "./runtime-event-ingress.ts"

const actor = bridgeActorId("owner-1")
const conversation = commanderConversationId("commander:global")
const now = new Date("2026-10-13T12:00:00.000Z")
const run = promisify(execFile)

class Runtime implements CommanderRuntime {
  prompts: string[] = []
  async prompt(input: Parameters<CommanderRuntime["prompt"]>[0]) { this.prompts.push(input.text); return { state: "accepted" as const, turnId: input.turnId } }
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
  const event = { conversationId: conversation, turnId: turnIdForRequest(bridgeRequestId("request-start")), cursor: streamCursor(1), deliveryId: "event-1", kind: "delta" as const, text: "working" }
  assert.deepEqual(await ingress.deliver({ token: "not-a-runtime-proof" }, event), { ok: false, reason: "unauthenticated" })
  assert.deepEqual(await ingress.deliver(authority.issueRuntimeEventProof(), event), { ok: true, state: "applied" })
})

test("private future-task delivery is authenticated, receipt-idempotent, and reconcilable", async () => {
  const authority = new EphemeralTestAuthority({ actorId: actor, conversationId: conversation, now: () => now })
  const controller = new CommanderBridgeController({ actorId: actor, conversationId: conversation, runtime: new Runtime(), store: new InMemoryConversationStore(), verifier: authority, now: () => now })
  const server = createCommanderBridgeNodeListener(new CommanderBridgeHttpService(controller), { identity: "operator-identity", store: new InMemoryFutureTaskDeliveryStore() })
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve))
  const address = server.address()
  if (!address || typeof address === "string") throw new Error("Missing loopback address")
  const endpoint = `http://127.0.0.1:${address.port}/private/future-tasks/deliveries`
  const body = { task_id: "task-1", text: "Check in", references: ["repo:digitaltwin"], due_at: "2026-10-13T12:00:00Z", timezone: "UTC", delivery_key: "delivery-1" }
  try {
    const rejected = await fetch(endpoint, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) })
    assert.equal(rejected.status, 401)
    const first = await fetch(endpoint, { method: "POST", headers: { authorization: "Bearer operator-identity", "content-type": "application/json" }, body: JSON.stringify(body) })
    const receipt = await first.json()
    const duplicate = await fetch(endpoint, { method: "POST", headers: { authorization: "Bearer operator-identity", "content-type": "application/json" }, body: JSON.stringify(body) })
    assert.equal(first.status, 200)
    assert.deepEqual(await duplicate.json(), receipt)
    const reconciled = await fetch(`${endpoint}/delivery-1`, { headers: { authorization: "Bearer operator-identity" } })
    assert.deepEqual(await reconciled.json(), receipt)
    const panel = await controller.open((await authority.issue({ action: "read" })))
    assert.equal(panel.ok && panel.conversation.events.at(-1)?.text, "Check in")
  } finally { await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve())) }
})

test("a Ruby client completes the private future-task delivery and reconciliation protocol", async () => {
  const authority = new EphemeralTestAuthority({ actorId: actor, conversationId: conversation, now: () => now })
  const controller = new CommanderBridgeController({ actorId: actor, conversationId: conversation, runtime: new Runtime(), store: new InMemoryConversationStore(), verifier: authority, now: () => now })
  const server = createCommanderBridgeNodeListener(new CommanderBridgeHttpService(controller), { identity: "ruby-operator-identity", store: new InMemoryFutureTaskDeliveryStore() })
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve))
  const address = server.address()
  if (!address || typeof address === "string") throw new Error("Missing loopback address")
  const program = [
    'require "net/http"', 'require "json"',
    'endpoint = URI(ARGV.fetch(0)); identity = ARGV.fetch(1)',
    'request = Net::HTTP::Post.new(endpoint, { "Authorization" => "Bearer #{identity}", "Content-Type" => "application/json" })',
    'request.body = JSON.generate({ task_id: "ruby-task", text: "Ruby delivery", references: ["repo:digitaltwin"], due_at: "2026-10-13T12:00:00Z", timezone: "UTC", delivery_key: "ruby-delivery" })',
    'receipt = JSON.parse(Net::HTTP.start(endpoint.host, endpoint.port) { |http| http.request(request) }.body)',
    'reconcile = URI("#{endpoint}/ruby-delivery"); read = Net::HTTP::Get.new(reconcile, { "Authorization" => "Bearer #{identity}" }); resolved = JSON.parse(Net::HTTP.start(reconcile.host, reconcile.port) { |http| http.request(read) }.body)',
    'abort "mismatch" unless receipt == resolved && receipt.fetch("delivery_key") == "ruby-delivery"',
    'puts JSON.generate(receipt)'
  ].join(";")
  try {
    const result = await run("ruby", ["-e", program, `http://127.0.0.1:${address.port}/private/future-tasks/deliveries`, "ruby-operator-identity"])
    assert.deepEqual(JSON.parse(result.stdout), { delivery_key: "ruby-delivery", commander_item_id: "future-task:ruby-delivery" })
  } finally { await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve())) }
})
