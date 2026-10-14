import assert from "node:assert/strict"
import { once } from "node:events"
import { createServer } from "node:http"
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test from "node:test"
import { CommanderDecisionContinuationHandler } from "./commander-decision-continuation-handler.ts"
import { FileCommanderAgentDecisionStore } from "./file-commander-agent-decision-store.ts"
import { OpenCodeHttpSessionClient, OpenCodeSessionContinuation } from "./opencode-continuation.ts"

test("continues an agent session through persisted recorded provenance after restart", async (t) => {
  const received: Array<Readonly<{ url: string; body: string }>> = []
  const server = createServer(async (request, response) => {
    const chunks: Buffer[] = []
    for await (const chunk of request) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk))
    const body = Buffer.concat(chunks).toString("utf8")
    received.push({ url: request.url ?? "", body })
    response.statusCode = request.url?.endsWith("/prompt") ? 200 : 200
    response.end("{}")
  })
  try {
    await listen(server)
  } catch {
    t.skip("local listener is unavailable in this sandbox; Docker exercises the fixture")
    return
  }
  const address = server.address()
  assert.notEqual(typeof address, "string")
  const origin = `http://127.0.0.1:${address.port}`
  const directory = await mkdtemp(join(tmpdir(), "commander-decision-"))
  const store = new FileCommanderAgentDecisionStore({ directory })
  const first = handler(store, origin)
  assert.equal(await first.recordAgentSession({
    id: "decision-release",
    provenance: { runtimeId: "opencode:sidecar", projectId: "project-release", sessionId: "ses_agent", messageId: "msg_started" },
  }), "recorded")

  const restarted = handler(new FileCommanderAgentDecisionStore({ directory }), origin)
  assert.deepEqual(await restarted.continueDecision({ decisionId: "decision-release", requestId: "follow-up-1", text: "Continue the release task." }), { ok: true, state: "continued" })
  assert.deepEqual(received.map((entry) => entry.url), [
    "/api/session/ses_agent",
    "/api/session/ses_agent/message/msg_started",
    "/api/session/ses_agent/prompt",
  ])
  assert.deepEqual(JSON.parse(received[2]!.body), {
    id: "msg_commander_70d157e58889f9fc469997da74d7a1ebb4dd579dd04b35a4e82ee913aed1ab93",
    text: "Continue the release task.",
    metadata: { fromCommander: true, commanderRequestDigest: "c41ade61808eca7ddd445201eba55b21f3e35970867382b24f182ccd9dae09ae" },
    resume: true,
  })
  const [file] = await readdir(directory)
  assert.ok(file)
  const persisted = await readFile(join(directory, file), "utf8")
  assert.equal(persisted.includes("function"), false)
  await close(server)
  await rm(directory, { recursive: true, force: true })
})

test("does not use caller-supplied provenance or change a recorded decision", async () => {
  const store = new MemoryStore()
  const subject = new CommanderDecisionContinuationHandler({
    decisions: store,
    continuation: new OpenCodeSessionContinuation({ client: new MissingClient() }),
  })
  assert.equal(await subject.recordAgentSession({
    id: "decision-1",
    provenance: { runtimeId: "opencode:sidecar", projectId: "project-a", sessionId: "ses_original", messageId: "msg_original" },
  }), "recorded")
  assert.equal(await subject.recordAgentSession({
    id: "decision-1",
    provenance: { runtimeId: "opencode:sidecar", projectId: "project-b", sessionId: "ses_other", messageId: "msg_other" },
  }), "conflict")
  assert.deepEqual(await subject.continueDecision({ decisionId: "missing", requestId: "request-1", text: "Continue" }), { ok: false, reason: "decision_missing" })
})

function handler(store: FileCommanderAgentDecisionStore, origin: string): CommanderDecisionContinuationHandler {
  return new CommanderDecisionContinuationHandler({
    decisions: store,
    continuation: new OpenCodeSessionContinuation({
      client: new OpenCodeHttpSessionClient({ origin, runtimeId: "opencode:sidecar", fetch: { fetch } }),
    }),
  })
}

class MemoryStore {
  private decision: { id: string; provenance: { runtimeId: string; projectId: string; sessionId: string; messageId: string } } | undefined

  async load(id: string) {
    return this.decision?.id === id ? this.decision : undefined
  }

  async save(decision: { id: string; provenance: { runtimeId: string; projectId: string; sessionId: string; messageId: string } }) {
    if (this.decision && JSON.stringify(this.decision) !== JSON.stringify(decision)) return "conflict" as const
    this.decision = decision
    return "saved" as const
  }
}

class MissingClient {
  async session() { return "missing" as const }
  async message() { return "missing" as const }
  async prompt() { return "missing" as const }
}

async function close(server: ReturnType<typeof createServer>): Promise<void> {
  server.close()
  await once(server, "close")
}

async function listen(server: ReturnType<typeof createServer>): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.once("listening", resolve)
    server.once("error", reject)
    server.listen(0, "127.0.0.1")
  })
}
