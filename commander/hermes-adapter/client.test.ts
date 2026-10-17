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
    if (url.pathname === "/v1/runs") return Response.json({ run_id: "run_1", session_id: "session_1", status: "started" })
    if (url.pathname === "/api/model/set") return Response.json({ ok: true })
    if (url.pathname === "/v1/runs/run_1") return Response.json({ run_id: "run_1", session_id: "session_1", status: "completed" })
    if (url.pathname === "/v1/runs/run_1/events") return new Response("id: 4\ndata: {\"seq\":4,\"type\":\"run.completed\",\"run_id\":\"run_1\"}\n\n", { headers: { "Content-Type": "text/event-stream" } })
    return Response.json({})
  }
  const client = new HermesGatewayClient(new URL("http://127.0.0.1:8642"), "adapter-only-token", fixture)
  assert.deepEqual(await client.start({ text: "ping", sessionID: "session_1", model: "configured-model", idempotencyKey: "request-1" }), { runID: "run_1", sessionID: "session_1", status: "started" })
  assert.equal((await client.status("run_1")).status, "completed")
  await client.setModel({ provider: "operator", model: "configured-model" })
  assert.deepEqual(await Array.fromAsync(client.events("run_1", 3)), [{ seq: 4, type: "run.completed", run_id: "run_1" }])
  await client.steer("run_1", "be brief")
  await client.stop("run_1")
  assert.deepEqual(requests, [
    { path: "/v1/runs", method: "POST", authorization: "Bearer adapter-only-token", idempotency: "request-1", body: { input: "ping", session_id: "session_1", model: "configured-model" } },
    { path: "/v1/runs/run_1", method: "GET", authorization: "Bearer adapter-only-token", idempotency: null, body: undefined },
    { path: "/api/model/set", method: "POST", authorization: "Bearer adapter-only-token", idempotency: null, body: { scope: "main", provider: "operator", model: "configured-model" } },
    { path: "/v1/runs/run_1/events", method: "GET", authorization: "Bearer adapter-only-token", idempotency: null, body: undefined },
    { path: "/v1/runs/run_1/steer", method: "POST", authorization: "Bearer adapter-only-token", idempotency: null, body: { input: "be brief" } },
    { path: "/v1/runs/run_1/stop", method: "POST", authorization: "Bearer adapter-only-token", idempotency: null, body: undefined },
  ])
})
