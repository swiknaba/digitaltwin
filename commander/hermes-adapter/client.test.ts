import assert from "node:assert/strict"
import test from "node:test"
import { HermesGatewayClient } from "./client"

test("uses Hermes durable run, control, and SSE contracts", async () => {
  const requests: Array<{ path: string; method: string; authorization: string | null; idempotency: string | null; body: unknown }> = []
  const fixture: typeof fetch = async (input, init) => {
    const url = new URL(input instanceof URL ? input : input.toString())
    const headers = new Headers(init?.headers)
    const body = typeof init?.body === "string" ? JSON.parse(init.body) : undefined
    requests.push({ path: url.pathname, method: init?.method ?? "GET", authorization: headers.get("Authorization"), idempotency: headers.get("Idempotency-Key"), body })
    if (url.pathname === "/v1/runs") return new Response(JSON.stringify({ run_id: "run_1", status: "queued", replayed: false }), { status: 202 })
    if (url.pathname === "/api/model/options") return Response.json({ providers: [{ slug: "operator", name: "Operator", models: ["configured-model"] }] })
    if (url.pathname === "/v1/runs/run_1") return Response.json({ run_id: "run_1", status: "completed" })
    if (url.pathname === "/v1/runs/run_1/events") return new Response("id: 4\ndata: {\"seq\":4,\"type\":\"run.completed\",\"run_id\":\"run_1\"}\n\n", { headers: { "Content-Type": "text/event-stream" } })
    if (url.pathname === "/api/sessions/session_1/messages") return Response.json({ data: [{ role: "user", content: "ping" }, { role: "assistant", content: "pong" }] })
    return Response.json({})
  }
  const client = new HermesGatewayClient(new URL("http://127.0.0.1:8642"), "adapter-only-token", fixture)
  assert.deepEqual(await client.start({ text: "ping", sessionID: "session_1", model: { provider: "operator", model: "configured-model" }, idempotencyKey: "request-1" }), { runID: "run_1", sessionID: "session_1", status: "queued" })
  assert.equal((await client.status("run_1")).status, "completed")
  assert.deepEqual(await client.models(), [{ provider: "operator", providerName: "Operator", model: "configured-model" }])
  assert.deepEqual(await Array.fromAsync(client.events("run_1", 3)), [{ seq: 4, type: "run.completed", run_id: "run_1" }])
  assert.deepEqual(await client.history("session_1"), [{ role: "user", content: "ping" }, { role: "assistant", content: "pong" }])
  await client.steer("run_1", "be brief")
  await client.stop("run_1")
  assert.deepEqual(requests, [
    { path: "/v1/runs", method: "POST", authorization: "Bearer adapter-only-token", idempotency: "request-1", body: { input: "ping", session_id: "session_1", provider: "operator", model: "configured-model", require_model_lock: true } },
    { path: "/v1/runs/run_1", method: "GET", authorization: "Bearer adapter-only-token", idempotency: null, body: undefined },
    { path: "/api/model/options", method: "GET", authorization: "Bearer adapter-only-token", idempotency: null, body: undefined },
    { path: "/v1/runs/run_1/events", method: "GET", authorization: "Bearer adapter-only-token", idempotency: null, body: undefined },
    { path: "/api/sessions/session_1/messages", method: "GET", authorization: "Bearer adapter-only-token", idempotency: null, body: undefined },
    { path: "/v1/runs/run_1/steer", method: "POST", authorization: "Bearer adapter-only-token", idempotency: null, body: { input: "be brief" } },
    { path: "/v1/runs/run_1/stop", method: "POST", authorization: "Bearer adapter-only-token", idempotency: null, body: undefined },
  ])
})

test("treats a missing persisted session history as an empty transcript", async () => {
  const client = new HermesGatewayClient(
    new URL("http://127.0.0.1:8642"),
    "adapter-only-token",
    async () => new Response(JSON.stringify({ error: "missing" }), { status: 404 }),
  )

  assert.deepEqual(await client.history("missing-session"), [])
})
