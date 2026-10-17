import assert from "node:assert/strict"
import test from "node:test"
import { OpenCodeHttpGateway } from "./gateway"

test("uses the installed OpenCode HTTP envelopes, top-level provenance, and assistant content", async () => {
  const calls: Array<Readonly<{ path: string; body: unknown; authorization: string | null }>> = []
  const request: typeof fetch = async (input, init) => {
    const url = input instanceof URL ? input : new URL(input.toString())
    const body = typeof init?.body === "string" ? JSON.parse(init.body) : undefined
    const headers = new Headers(init?.headers)
    calls.push({ path: `${url.pathname}${url.search}`, body, authorization: headers.get("Authorization") })
    const response = (() => {
      if (url.pathname === "/api/project") return [{ id: "project-1", canonical: "/srv/digitaltwin", name: "digitaltwin" }]
      if (url.pathname === "/api/session" && init?.method === "POST") return { data: { id: "ses_hermes", projectID: "project-1" } }
      if (url.pathname === "/api/session/ses_hermes/prompt") {
        return { data: { id: "msg_hermes", type: "user", text: body.text, metadata: body.metadata } }
      }
      if (url.pathname === "/api/session/ses_hermes") return { data: { id: "ses_hermes", projectID: "project-1" } }
      if (url.pathname === "/api/session/ses_hermes/message") {
        return { data: [{ id: "msg_reply", type: "assistant", content: [{ type: "reasoning", text: "private" }, { type: "text", text: "Completed." }] }] }
      }
      throw new Error(`Unexpected request: ${url.pathname}`)
    })()
    return new Response(JSON.stringify(response), { status: 200, headers: { "Content-Type": "application/json" } })
  }
  const gateway = new OpenCodeHttpGateway(new URL("http://127.0.0.1:3086"), "approved-private-password", request)
  assert.deepEqual(await gateway.listProjects(), [{ id: "project-1", name: "digitaltwin", directory: "/srv/digitaltwin" }])
  assert.deepEqual(await gateway.createSession({ id: "ses_hermes", directory: "/srv/digitaltwin" }), { id: "ses_hermes", projectID: "project-1" })
  assert.deepEqual(await gateway.prompt({ sessionID: "ses_hermes", messageID: "msg_hermes", text: "Start.", metadata: { fromCommander: true } }), {
    id: "msg_hermes",
    type: "user",
    text: "Start.",
    metadata: { fromCommander: true },
  })
  assert.deepEqual(await gateway.readSession("ses_hermes"), { id: "ses_hermes", projectID: "project-1" })
  assert.deepEqual(await gateway.readMessages("ses_hermes"), [{
    id: "msg_reply",
    type: "assistant",
    content: [{ type: "reasoning", text: "private" }, { type: "text", text: "Completed." }],
  }])
  assert.deepEqual(calls, [
    { path: "/api/project", body: undefined, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
    { path: "/api/session", body: { id: "ses_hermes", location: { directory: "/srv/digitaltwin" } }, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
    { path: "/api/session/ses_hermes/prompt", body: { id: "msg_hermes", text: "Start.", metadata: { fromCommander: true }, resume: true }, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
    { path: "/api/session/ses_hermes", body: undefined, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
    { path: "/api/session/ses_hermes/message?order=desc&limit=100", body: undefined, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
  ])
})

test("fails before network access when no OpenCode sidecar password was explicitly provided", async () => {
  let invoked = false
  const request: typeof fetch = async () => {
    invoked = true
    return new Response("{}")
  }
  const gateway = new OpenCodeHttpGateway(new URL("http://127.0.0.1:3086"), undefined, request)
  await assert.rejects(gateway.listProjects(), /authorization is not configured/)
  assert.equal(invoked, false)
})

test("rejects a non-loopback sidecar endpoint before it can attach a Basic credential", () => {
  let invoked = false
  const request: typeof fetch = async () => {
    invoked = true
    return new Response("{}")
  }
  assert.throws(
    () => new OpenCodeHttpGateway(new URL("https://opencode.example.test"), "approved-private-password", request),
    /http loopback origin/,
  )
  assert.equal(invoked, false)
})
