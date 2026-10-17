import assert from "node:assert/strict"
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises"
import { join } from "node:path"
import test from "node:test"
import { OpenCodeHttpGateway, ServiceRegistrationOpenCodeSidecar, staticOpenCodeSidecar } from "./gateway"

test("uses the installed OpenCode HTTP envelopes and only selects enabled explicit worker models", async () => {
  const calls: Array<Readonly<{ path: string; body: unknown; authorization: string | null }>> = []
  const request: typeof fetch = async (input, init) => {
    const url = input instanceof URL ? input : new URL(input.toString())
    const body = typeof init?.body === "string" ? JSON.parse(init.body) : undefined
    const headers = new Headers(init?.headers)
    calls.push({ path: `${url.pathname}${url.search}`, body, authorization: headers.get("Authorization") })
    const response = (() => {
      if (url.pathname === "/api/project") return [{ id: "project-1", canonical: "/srv/digitaltwin", name: "digitaltwin" }]
      if (url.pathname === "/api/model") return { data: [
        { providerID: "anthropic", id: "claude-opus-5-5", enabled: true, variants: [{ id: "high" }] },
        { providerID: "opencode", id: "nemotron-3.5-super-vl-free", enabled: false, variants: [] },
      ] }
      if (url.pathname === "/api/session" && init?.method === "POST") return { data: { id: "ses_hermes", projectID: "project-1" } }
      if (url.pathname === "/api/session/ses_hermes/model" && init?.method === "POST") return undefined
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
  const gateway = new OpenCodeHttpGateway(staticOpenCodeSidecar(new URL("http://127.0.0.1:3086"), "approved-private-password"), request)
  assert.deepEqual(await gateway.listProjects(), [{ id: "project-1", name: "digitaltwin", directory: "/srv/digitaltwin" }])
  assert.deepEqual(await gateway.listAvailableModels("/srv/digitaltwin"), [{ model: { providerID: "anthropic", modelID: "claude-opus-5-5" }, variants: ["high"] }])
  assert.deepEqual(await gateway.createSession({ id: "ses_hermes", directory: "/srv/digitaltwin" }), { id: "ses_hermes", projectID: "project-1" })
  assert.deepEqual(await gateway.createSession({ id: "ses_hermes", directory: "/srv/digitaltwin", model: { providerID: "anthropic", modelID: "claude-opus-5-5", variant: "high" } }), { id: "ses_hermes", projectID: "project-1" })
  await gateway.selectSessionModel({ sessionID: "ses_hermes", model: { providerID: "anthropic", modelID: "claude-opus-5-5", variant: "high" } })
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
    { path: "/api/model?location%5Bdirectory%5D=%2Fsrv%2Fdigitaltwin", body: undefined, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
    { path: "/api/session", body: { id: "ses_hermes", location: { directory: "/srv/digitaltwin" } }, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
    { path: "/api/session", body: { id: "ses_hermes", location: { directory: "/srv/digitaltwin" }, model: { providerID: "anthropic", id: "claude-opus-5-5", variant: "high" } }, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
    { path: "/api/session/ses_hermes/model", body: { model: { providerID: "anthropic", id: "claude-opus-5-5", variant: "high" } }, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
    { path: "/api/session/ses_hermes/prompt", body: { id: "msg_hermes", text: "Start.", metadata: { fromCommander: true }, resume: true }, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
    { path: "/api/session/ses_hermes", body: undefined, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
    { path: "/api/session/ses_hermes/message?order=desc&limit=100", body: undefined, authorization: "Basic b3BlbmNvZGU6YXBwcm92ZWQtcHJpdmF0ZS1wYXNzd29yZA==" },
  ])
})

test("normalizes the current durable inbox admission response", async () => {
  const request: typeof fetch = async (input) => {
    const url = input instanceof URL ? input : new URL(input.toString())
    assert.equal(url.pathname, "/api/session/ses_hermes/prompt")
    return new Response(JSON.stringify({
      data: {
        id: "msg_hermes",
        sessionID: "ses_hermes",
        type: "user",
        payload: { text: "Start.", metadata: { fromCommander: true } },
      },
    }), { status: 200, headers: { "Content-Type": "application/json" } })
  }
  const gateway = new OpenCodeHttpGateway(staticOpenCodeSidecar(new URL("http://127.0.0.1:3086"), "approved-private-password"), request)
  assert.deepEqual(await gateway.prompt({ sessionID: "ses_hermes", messageID: "msg_hermes", text: "Start.", metadata: { fromCommander: true } }), {
    id: "msg_hermes",
    sessionID: "ses_hermes",
    type: "user",
    text: "Start.",
    metadata: { fromCommander: true },
  })
})

test("waits for the exact session to become idle", async () => {
  const calls: string[] = []
  const request: typeof fetch = async (input) => {
    const url = input instanceof URL ? input : new URL(input.toString())
    calls.push(`${url.pathname}${url.search}`)
    return new Response(null, { status: 204 })
  }
  const gateway = new OpenCodeHttpGateway(staticOpenCodeSidecar(new URL("http://127.0.0.1:3086"), "approved-private-password"), request)
  await gateway.waitSession("ses_hermes")
  assert.deepEqual(calls, ["/api/experimental/session/ses_hermes/wait"])
})

test("preserves a completed assistant provider failure without exposing its message", async () => {
  const request: typeof fetch = async (input) => {
    const url = input instanceof URL ? input : new URL(input.toString())
    assert.equal(url.pathname, "/api/session/ses_hermes/message")
    return new Response(JSON.stringify({
      data: [{
        id: "msg_failed",
        type: "assistant",
        agent: "build",
        model: { providerID: "anthropic", id: "claude-opus-5-5", variant: "high" },
        content: [],
        finish: "error",
        error: { type: "provider.auth", message: "private detail", status: 403 },
        time: { created: 1, completed: 2 },
      }],
    }), { status: 200, headers: { "Content-Type": "application/json" } })
  }
  const gateway = new OpenCodeHttpGateway(staticOpenCodeSidecar(new URL("http://127.0.0.1:3086"), "approved-private-password"), request)
  assert.deepEqual(await gateway.readMessages("ses_hermes"), [{
    id: "msg_failed",
    type: "assistant",
    model: { providerID: "anthropic", modelID: "claude-opus-5-5", variant: "high" },
    finish: "error",
    error: { type: "provider.auth", status: 403 },
  }])
})

test("fails before network access until service-registration discovery is explicitly authorized", async () => {
  let invoked = false
  const request: typeof fetch = async () => {
    invoked = true
    return new Response("{}")
  }
  const gateway = new OpenCodeHttpGateway(staticOpenCodeSidecar(new URL("http://127.0.0.1:3086"), undefined), request)
  await assert.rejects(gateway.listProjects(), /registration access is not configured/)
  assert.equal(invoked, false)
})

test("rejects a non-loopback sidecar endpoint before it can attach a Basic credential", () => {
  let invoked = false
  const request: typeof fetch = async () => {
    invoked = true
    return new Response("{}")
  }
  assert.throws(
    () => staticOpenCodeSidecar(new URL("https://opencode.example.test"), "approved-private-password"),
    /http loopback origin/,
  )
  assert.equal(invoked, false)
})

test("uses the official service registration, verifies it, and rediscovers after a sidecar rotation", async () => {
  const root = await mkdtemp(join(process.cwd(), "local/tmp/hermes-mcp-registration-"))
  const registration = join(root, "service-local.json")
  const pid = process.pid
  const writeRegistration = async (password: string) => {
    await writeFile(registration, `${JSON.stringify({ id: "service", version: "2.0.27", url: "http://127.0.0.1:3086", pid, password })}\n`, { mode: 0o600 })
    await chmod(registration, 0o600)
  }
  await writeRegistration("first-private-password")
  let healthProbes = 0
  const projectAuthorizations: string[] = []
  const request: typeof fetch = async (input, init) => {
    const url = input instanceof URL ? input : new URL(input.toString())
    const authorization = new Headers(init?.headers).get("authorization") ?? ""
    if (url.pathname === "/api/info") {
      healthProbes += 1
      return new Response(JSON.stringify({ version: "2.0.27", pid }), { status: 200, headers: { "Content-Type": "application/json" } })
    }
    if (url.pathname === "/api/project") {
      projectAuthorizations.push(authorization)
      if (projectAuthorizations.length === 1) {
        await writeRegistration("second-private-password")
        return new Response("{}", { status: 401 })
      }
      return new Response("[]", { status: 200, headers: { "Content-Type": "application/json" } })
    }
    throw new Error(`Unexpected request: ${url.pathname}`)
  }
  try {
    const sidecar = new ServiceRegistrationOpenCodeSidecar(registration, request)
    const gateway = new OpenCodeHttpGateway(sidecar, request)
    assert.deepEqual(await gateway.listProjects(), [])
    assert.equal(healthProbes, 2)
    assert.deepEqual(projectAuthorizations, [
      "Basic b3BlbmNvZGU6Zmlyc3QtcHJpdmF0ZS1wYXNzd29yZA==",
      "Basic b3BlbmNvZGU6c2Vjb25kLXByaXZhdGUtcGFzc3dvcmQ=",
    ])
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test("normalizes a registered wildcard bind to loopback before using its private credential", async () => {
  const root = await mkdtemp(join(process.cwd(), "local/tmp/hermes-mcp-registration-wildcard-"))
  const registration = join(root, "service-local.json")
  await writeFile(registration, `${JSON.stringify({ url: "http://0.0.0.0:3086", pid: process.pid, password: "private" })}\n`, { mode: 0o600 })
  await chmod(registration, 0o600)
  const hosts: string[] = []
  const request: typeof fetch = async (input) => {
    const url = input instanceof URL ? input : new URL(input.toString())
    hosts.push(url.hostname)
    return new Response(JSON.stringify({ version: "2.0.27", pid: process.pid }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    })
  }
  try {
    const source = new ServiceRegistrationOpenCodeSidecar(registration, request)
    const sidecar = await source.resolve()
    assert.equal(sidecar.endpoint.hostname, "127.0.0.1")
    assert.deepEqual(hosts, ["127.0.0.1"])
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test("refuses a service registration whose permissions expose the private credential", async () => {
  const root = await mkdtemp(join(process.cwd(), "local/tmp/hermes-mcp-registration-mode-"))
  const registration = join(root, "service-local.json")
  await writeFile(registration, `${JSON.stringify({ url: "http://127.0.0.1:3086", pid: process.pid, password: "private" })}\n`, { mode: 0o600 })
  await chmod(registration, 0o644)
  try {
    const source = new ServiceRegistrationOpenCodeSidecar(registration)
    await assert.rejects(source.resolve(), /permissions must exclude group and other access/)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test("refuses a service registration with a non-loopback endpoint before its credential is sent", async () => {
  const root = await mkdtemp(join(process.cwd(), "local/tmp/hermes-mcp-registration-endpoint-"))
  const registration = join(root, "service-local.json")
  await writeFile(registration, `${JSON.stringify({ url: "https://opencode.example.test", pid: process.pid, password: "private" })}\n`, { mode: 0o600 })
  let invoked = false
  const request: typeof fetch = async () => {
    invoked = true
    return new Response("{}")
  }
  try {
    const source = new ServiceRegistrationOpenCodeSidecar(registration, request)
    await assert.rejects(source.resolve(), /http loopback origin/)
    assert.equal(invoked, false)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})
