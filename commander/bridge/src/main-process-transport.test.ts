import assert from "node:assert/strict"
import test from "node:test"
import { CommanderMainProcessTransport } from "./main-process-transport.ts"

test("main-process transport issues the proof and never returns it to its caller", async () => {
  const requests: Array<{ url: string; authorization: string; body: string }> = []
  const client = new CommanderMainProcessTransport({
    baseUrl: "http://127.0.0.1:4312",
    capabilityIssuer: { issue: async (action) => { assert.equal(action, "prompt"); return { token: "ephemeral-main-only-proof" } } },
    fetch: { fetch: async (url, init) => { requests.push({ url, authorization: init.headers.authorization ?? "", body: init.body }); return { status: 200, json: async () => ({ ok: true, state: "dispatched" }) } } },
  })
  const result = await client.prompt("request-1", "hello")
  assert.deepEqual(result, { ok: true, state: "dispatched" })
  assert.deepEqual(requests, [{ url: "http://127.0.0.1:4312/v1/commander/prompt", authorization: "Bearer ephemeral-main-only-proof", body: "{\"requestId\":\"request-1\",\"text\":\"hello\"}" }])
  assert.equal(JSON.stringify(result).includes("ephemeral-main-only-proof"), false)
})

test("main-process transport fails closed for an unsafe endpoint or a transport error", async () => {
  assert.throws(() => new CommanderMainProcessTransport({ baseUrl: "http://bridge.example.test", capabilityIssuer: { issue: async () => ({ token: "proof" }) }, fetch: { fetch: async () => { throw new Error("unreachable") } } }))
  const client = new CommanderMainProcessTransport({ baseUrl: "http://127.0.0.1:4312", capabilityIssuer: { issue: async () => ({ token: "proof" }) }, fetch: { fetch: async () => { throw new Error("unreachable") } } })
  assert.deepEqual(await client.cancel("request-1"), { ok: false, reason: "uncertain" })
})
