import assert from "node:assert/strict"
import test from "node:test"
import { type OpenCodeMessageProvenance } from "./contract.ts"
import { OpenCodeHttpSessionClient, OpenCodeSessionContinuation, type OpenCodeSessionClient } from "./opencode-continuation.ts"

const provenance: OpenCodeMessageProvenance = { runtimeId: "opencode:developer", projectId: "project-a", sessionId: "ses_child", messageId: "msg_reply", parentSessionId: "ses_parent" }

class Client implements OpenCodeSessionClient {
  readonly calls: Array<Readonly<{ kind: "session" | "message" | "prompt"; input: OpenCodeMessageProvenance | Readonly<{ provenance: OpenCodeMessageProvenance; inputId: string; text: string; requestDigest: string; metadata: Readonly<{ fromCommander: true; commanderRequestDigest: string }> }> }>> = []
  sessionState: "found" | "missing" | "inaccessible" = "found"
  messageState: "found" | "missing" | "inaccessible" = "found"
  promptState: "accepted" | "stale" | "missing" | "inaccessible" | "unknown" = "accepted"

  async session(input: OpenCodeMessageProvenance) { this.calls.push({ kind: "session", input }); return this.sessionState }
  async message(input: OpenCodeMessageProvenance) { this.calls.push({ kind: "message", input }); return this.messageState }
  async prompt(input: Readonly<{ provenance: OpenCodeMessageProvenance; inputId: string; text: string; requestDigest: string; metadata: Readonly<{ fromCommander: true; commanderRequestDigest: string }> }>) { this.calls.push({ kind: "prompt", input }); return this.promptState }
}

async function subject() {
  const client = new Client()
  return { client, service: new OpenCodeSessionContinuation({ client }) }
}

const continuation = { provenance, requestId: "continue-1", text: "Follow up" }

test("routes Commander provenance to exactly one ordinary OpenCode input", async () => {
  const input = await subject()
  assert.deepEqual(await input.service.continue(continuation), { ok: true, state: "continued" })
  assert.deepEqual(input.client.calls.slice(0, 2), [{ kind: "session", input: provenance }, { kind: "message", input: provenance }])
  assert.deepEqual(input.client.calls[2], {
    kind: "prompt",
    input: {
      provenance,
      inputId: "msg_commander_5f9ade5d32920016e80ac31625c62b12bff9d5d22140b3a904423a717f12f761",
      text: "Follow up",
      requestDigest: "7d28f801df95601ae383dfa6b42e6b3de7b57d8a0c19892e9bc227ffb230d7c6",
      metadata: { fromCommander: true, commanderRequestDigest: "7d28f801df95601ae383dfa6b42e6b3de7b57d8a0c19892e9bc227ffb230d7c6" },
    },
  })
})

test("reuses the exact same normal input ID on retry", async () => {
  const input = await subject()
  assert.deepEqual(await input.service.continue(continuation), { ok: true, state: "continued" })
  assert.deepEqual(await input.service.continue(continuation), { ok: true, state: "continued" })
  const prompts = input.client.calls.filter((call) => call.kind === "prompt")
  assert.equal(prompts.length, 2)
  assert.equal((prompts[0]!.input as Readonly<{ inputId: string }>).inputId, (prompts[1]!.input as Readonly<{ inputId: string }>).inputId)
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
  const resumed = new OpenCodeSessionContinuation({ client: input.client })
  assert.deepEqual(await resumed.continue(continuation), { ok: true, state: "continued" })
  const prompts = input.client.calls.filter((call) => call.kind === "prompt")
  assert.equal(prompts.length, 2)
  assert.equal((prompts[0]!.input as Readonly<{ inputId: string }>).inputId, (prompts[1]!.input as Readonly<{ inputId: string }>).inputId)
})

test("uses a deterministic input ID after process restart", async () => {
  const input = await subject()
  const resumed = new OpenCodeSessionContinuation({ client: input.client })
  assert.deepEqual(await resumed.continue(continuation), { ok: true, state: "continued" })
  const prompt = input.client.calls.find((call) => call.kind === "prompt")?.input as Readonly<{ inputId: string }>
  assert.equal(prompt.inputId, "msg_commander_5f9ade5d32920016e80ac31625c62b12bff9d5d22140b3a904423a717f12f761")
})

test("reconciles a matching conflict admission by deterministic body digest", async () => {
  const requests: Array<Readonly<{ url: string; method?: string; body?: string }>> = []
  const statuses = [200, 200, 409, 200]
  const client = new OpenCodeHttpSessionClient({
    origin: "https://opencode.example.test",
    runtimeId: provenance.runtimeId,
    fetch: {
      async fetch(url, init) {
        requests.push({ url, ...(init?.method === undefined ? {} : { method: init.method }), ...(init?.body === undefined ? {} : { body: init.body }) })
        return { status: statuses.shift() ?? 500, async json() { return { id: "msg_commander_test", metadata: { fromCommander: true, commanderRequestDigest: "digest" } } } }
      },
    },
  })
  assert.equal(await client.session(provenance), "found")
  assert.equal(await client.message(provenance), "found")
  assert.equal(await client.prompt({ provenance, inputId: "msg_commander_test", text: "Follow up", requestDigest: "digest", metadata: { fromCommander: true, commanderRequestDigest: "digest" } }), "accepted")
  assert.equal(requests.length, 4)
})

test("does not create a second input when a request id is reused with changed text", async () => {
  const input = await subject()
  await input.service.continue(continuation)
  input.client.promptState = "stale"
  assert.deepEqual(await input.service.continue({ ...continuation, text: "Changed body" }), { ok: false, reason: "stale" })
  const prompts = input.client.calls.filter((call) => call.kind === "prompt")
  assert.equal((prompts[0]!.input as Readonly<{ inputId: string }>).inputId, (prompts[1]!.input as Readonly<{ inputId: string }>).inputId)
})

test("uses the pinned ordinary OpenCode endpoint and carries only Commander provenance metadata", async () => {
  const requests: Array<Readonly<{ url: string; method?: string; body?: string }>> = []
  const client = new OpenCodeHttpSessionClient({
    origin: "https://opencode.example.test/ignored-path",
    runtimeId: "opencode:developer",
    fetch: {
      async fetch(url, init) {
        requests.push({ url, ...(init?.method === undefined ? {} : { method: init.method }), ...(init?.body === undefined ? {} : { body: init.body }) })
        return { status: 200, async json() { return {} } }
      },
    },
  })
  assert.equal(await client.session(provenance), "found")
  assert.equal(await client.message(provenance), "found")
  assert.equal(await client.prompt({ provenance, inputId: "msg_commander_test", text: "Follow up", requestDigest: "digest", metadata: { fromCommander: true, commanderRequestDigest: "digest" } }), "accepted")
  assert.deepEqual(requests, [
    { url: "https://opencode.example.test/api/session/ses_child" },
    { url: "https://opencode.example.test/api/session/ses_child/message/msg_reply" },
    { url: "https://opencode.example.test/api/session/ses_child/prompt", method: "POST", body: "{\"id\":\"msg_commander_test\",\"text\":\"Follow up\",\"metadata\":{\"fromCommander\":true,\"commanderRequestDigest\":\"digest\"},\"resume\":true}" },
  ])
})

test("keeps transient reads uncertain while preserving authorization failures", async () => {
  const client = new OpenCodeHttpSessionClient({
    origin: "https://opencode.example.test",
    runtimeId: provenance.runtimeId,
    fetch: { async fetch() { return { status: 503, async json() { return {} } } } },
  })
  assert.equal(await client.session(provenance), "unknown")
  const forbidden = new OpenCodeHttpSessionClient({
    origin: "https://opencode.example.test",
    runtimeId: provenance.runtimeId,
    fetch: { async fetch() { return { status: 403, async json() { return {} } } } },
  })
  assert.equal(await forbidden.session(provenance), "inaccessible")
})
