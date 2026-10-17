import assert from "node:assert/strict"
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises"
import { join } from "node:path"
import test from "node:test"
import futureTasks from "./future-tasks.ts"

type Request = Readonly<{ readonly url: string; readonly method: string; readonly body: Record<string, unknown>; readonly authorization: string }>
type RegisteredTool = Readonly<{ readonly execute: (input: Record<string, unknown>, tool: Readonly<{ readonly sessionID: string }>) => Promise<Readonly<{ readonly content: string }>> }>

test("sends Kirei-compatible create, disposition, and uncertainty-resolution requests", async () => {
  const temporaryRoot = join(process.cwd(), "local")
  await mkdir(temporaryRoot, { recursive: true })
  const directory = await mkdtemp(join(temporaryRoot, "future-tasks-contract-"))
  const secretFile = join(directory, "capability-secret")
  await writeFile(secretFile, "fixture-secret\n", "utf8")

  const requests: Request[] = []
  const originalFetch = globalThis.fetch
  let registered: RegisteredTool | undefined
  globalThis.fetch = async (url, init) => {
    const authorization = new Headers(init?.headers).get("authorization")
    assert.ok(authorization)
    assert.equal(typeof init?.body, "string")
    requests.push({ url: String(url), method: init?.method ?? "GET", body: JSON.parse(init?.body as string), authorization })
    return new Response(JSON.stringify({ id: "task-1" }), { status: 200, headers: { "content-type": "application/json" } })
  }

  try {
    await futureTasks.setup({
      options: {
        digitaltwinFutureTasksEndpoint: "https://future.example.test/v1/future-tasks",
        digitaltwinFutureTasksCapabilitySecretFile: secretFile,
        digitaltwinFutureTasksActor: "commander",
        digitaltwinFutureTasksOwner: true,
      },
      tool: {
        transform: async (callback: (editor: Readonly<{ readonly add: (tool: RegisteredTool) => void }>) => void) => callback({ add: (tool) => { registered = tool } }),
      },
    } as never)
    assert.ok(registered)

    await registered.execute({ operation: "create", idempotency_key: "create-1", text: "Check release", due_at: "2026-10-17T09:00:00Z" }, { sessionID: "ses_commander" })
    await registered.execute({ operation: "disposition", id: "task-1", expected_version: 2, disposition_key: "answer-1", outcome: "assessed" }, { sessionID: "ses_commander" })
    await registered.execute({ operation: "resolve_uncertain", id: "task-1", expected_version: 2, resolution_key: "resolve-1", outcome: "failed", reason: "delivery rejected" }, { sessionID: "ses_commander" })

    assert.deepEqual(requests.map((request) => [request.url, request.method, request.body]), [
      ["https://future.example.test/v1/future-tasks", "POST", { operation: "create", idempotency_key: "create-1", text: "Check release", due_at: "2026-10-17T09:00:00Z" }],
      ["https://future.example.test/v1/future-tasks/task-1/dispositions", "POST", { operation: "disposition", id: "task-1", expected_version: 2, disposition_key: "answer-1", outcome: "assessed" }],
      ["https://future.example.test/v1/future-tasks/task-1/resolution", "POST", { operation: "resolve_uncertain", id: "task-1", expected_version: 2, resolution_key: "resolve-1", outcome: "failed", reason: "delivery rejected" }],
    ])
    for (const request of requests) {
      const [payload] = request.authorization.slice("Bearer ".length).split(".")
      const capability = JSON.parse(Buffer.from(payload, "hex").toString("utf8"))
      assert.equal(capability.conversation, "opencode:ses_commander")
      assert.equal(capability.owner, true)
    }
  } finally {
    globalThis.fetch = originalFetch
    await rm(directory, { recursive: true, force: true })
  }
})
