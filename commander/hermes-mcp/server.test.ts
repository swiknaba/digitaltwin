import assert from "node:assert/strict"
import test from "node:test"
import { mkdir, mkdtemp, rm } from "node:fs/promises"
import { join } from "node:path"
import { CommanderDelegation } from "./delegation"
import { FileDelegationStore } from "./store"
import type { CommanderMessage, CommanderProject, CommanderSession, DelegationState, DelegationStore, Json, OpenCodeCommanderGateway } from "./contract"

function fixture() {
  let state: DelegationState = { revision: 0, decisions: {}, requests: {}, pending: {} }
  const prompts: Array<Readonly<{ sessionID: string; messageID: string; text: string; metadata: Readonly<Record<string, Json>> }>> = []
  let creates = 0
  const sessions = new Map<string, CommanderSession>()
  const projects: readonly CommanderProject[] = [{ id: "project-1", name: "digitaltwin", directory: "/srv/digitaltwin" }]
  const gateway: OpenCodeCommanderGateway = {
    listProjects: async () => projects,
    createSession: async ({ id, directory }) => {
      assert.equal(directory, "/srv/digitaltwin")
      creates += 1
      const session = { id, projectID: "project-1" }
      sessions.set(session.id, session)
      return session
    },
    prompt: async (input) => {
      prompts.push(input)
      return { id: input.messageID, type: "user", text: input.text, metadata: input.metadata }
    },
    waitSession: async () => undefined,
    readSession: async (sessionID) => {
      const session = sessions.get(sessionID)
      if (!session) throw new Error("not found")
      return session
    },
    readMessages: async () => [{ id: "msg_result", type: "assistant", text: "Finished." }],
  }
  const store: DelegationStore = { read: async () => state, write: async (next) => { state = next }, exclusive: async (work) => work() }
  return { delegation: () => new CommanderDelegation(gateway, store, "hermes-profile-local"), gateway, prompts, creates: () => creates, state: () => state, sessions }
}

test("lists projects and reads without dispatching a prompt", async () => {
  const f = fixture()
  assert.deepEqual(await f.delegation().listProjects(), [{ id: "project-1", name: "digitaltwin", directory: "/srv/digitaltwin" }])
  assert.equal(f.prompts.length, 0)
  await assert.rejects(f.delegation().read({ decisionID: "missing" }), /not found/)
  assert.equal(f.prompts.length, 0)
})

test("creates a precisely-provenanced normal project session and restores its stable reference after restart", async () => {
  const f = fixture()
  const first = await f.delegation().create({ projectID: "project-1", requestID: "create-1", text: "Investigate the regression." })
  assert.equal(f.creates(), 1)
  assert.match(String(first.decision_id), /^hermes-project-session-[a-f0-9]{64}$/)
  assert.match(String(first.message_id), /^msg_hermes_commander_[a-f0-9]{64}$/)
  assert.deepEqual(first.provenance, {
    source: "hermes-mcp",
    subject: "hermes-profile-local",
    project_id: "project-1",
    create_request_id: "create-1",
  })
  assert.deepEqual(f.prompts[0], {
    sessionID: first.session_id,
    messageID: first.message_id,
    text: "Commander-directed work:\n\nInvestigate the regression.",
    metadata: {
      fromCommander: true,
      commanderSource: "hermes-mcp",
      commanderProvenanceSubject: "hermes-profile-local",
      commanderDecisionID: first.decision_id,
      commanderProjectID: "project-1",
      commanderRequestID: "create-1",
    },
  })
  const retry = await f.delegation().create({ projectID: "project-1", requestID: "create-1", text: "Investigate the regression." })
  assert.equal(f.creates(), 1)
  assert.deepEqual(retry, first)
  const reloaded = f.delegation()
  const read = await reloaded.read({ decisionID: String(first.decision_id) })
  assert.deepEqual(read, {
    decision_id: first.decision_id,
    session_id: first.session_id,
    project_id: "project-1",
    provenance: first.provenance,
    latest_result: { id: "msg_result", type: "assistant", text: "Finished." },
  })
  assert.equal(f.prompts.length, 2)
})

test("continues only the persisted exact target and preserves idempotency after restart", async () => {
  const f = fixture()
  const created = await f.delegation().create({ projectID: "project-1", requestID: "create-1", text: "Start." })
  const result = await f.delegation().continue({ decisionID: String(created.decision_id), requestID: "continue-1", text: "Continue." })
  assert.deepEqual(result, {
    decision_id: created.decision_id,
    session_id: created.session_id,
    project_id: "project-1",
    request_id: "continue-1",
    provenance: created.provenance,
  })
  const again = await f.delegation().continue({ sessionID: String(created.session_id), requestID: "continue-1", text: "Continue." })
  assert.deepEqual(again, result)
  await assert.rejects(f.delegation().continue({ decisionID: String(created.decision_id), requestID: "continue-1", text: "different" }), /conflicts/)
  const afterRestart = f.delegation()
  await afterRestart.continue({ decisionID: String(created.decision_id), requestID: "continue-2", text: "Resume after restart." })
  assert.equal(f.prompts.length, 4)
  assert.equal(f.prompts.at(-1)?.sessionID, created.session_id)
  assert.equal(f.state().decisions[String(created.decision_id)]?.continued["continue-2"].length, 64)
})

test("rejects an OpenCode prompt admission that does not preserve metadata", async () => {
  const brokenGateway: OpenCodeCommanderGateway = {
    listProjects: async () => [{ id: "project-1", name: "digitaltwin", directory: "/srv/digitaltwin" }],
    createSession: async ({ id }) => ({ id, projectID: "project-1" }),
    prompt: async (input): Promise<CommanderMessage> => ({ id: input.messageID, type: "user", text: input.text, metadata: {} }),
    waitSession: async () => undefined,
    readSession: async () => ({ id: "ses_broken", projectID: "project-1" }),
    readMessages: async () => [],
  }
  let persisted: DelegationState = { revision: 0, decisions: {}, requests: {}, pending: {} }
  const state: DelegationStore = { read: async () => persisted, write: async (next) => { persisted = next }, exclusive: async (work) => work() }
  await assert.rejects(new CommanderDelegation(brokenGateway, state, "hermes-profile-local").create({ projectID: "project-1", requestID: "broken-1", text: "Fail safely." }), /admission conflicts/)
})

test("rejects an OpenCode prompt admission for a different session", async () => {
  const brokenGateway: OpenCodeCommanderGateway = {
    listProjects: async () => [{ id: "project-1", name: "digitaltwin", directory: "/srv/digitaltwin" }],
    createSession: async ({ id }) => ({ id, projectID: "project-1" }),
    prompt: async (input): Promise<CommanderMessage> => ({ id: input.messageID, sessionID: "ses_other", type: "user", text: input.text, metadata: input.metadata }),
    waitSession: async () => undefined,
    readSession: async () => ({ id: "ses_broken", projectID: "project-1" }),
    readMessages: async () => [],
  }
  let persisted: DelegationState = { revision: 0, decisions: {}, requests: {}, pending: {} }
  const state: DelegationStore = { read: async () => persisted, write: async (next) => { persisted = next }, exclusive: async (work) => work() }
  await assert.rejects(new CommanderDelegation(brokenGateway, state, "hermes-profile-local").create({ projectID: "project-1", requestID: "wrong-session-1", text: "Fail safely." }), /admission conflicts/)
})

test("reports a structured worker failure without its private provider message", async () => {
  const f = fixture()
  const created = await f.delegation().create({ projectID: "project-1", requestID: "failure-1", text: "Ping." })
  f.gateway.readMessages = async () => [{ id: "msg_failed", type: "assistant", model: { providerID: "anthropic", modelID: "claude-opus-5-5" }, finish: "error", error: { type: "provider.auth", status: 403 } }]
  assert.deepEqual(await f.delegation().read({ decisionID: String(created.decision_id) }), {
    decision_id: created.decision_id,
    session_id: created.session_id,
    project_id: "project-1",
    provenance: created.provenance,
    latest_result: { id: "msg_failed", type: "assistant", model: { providerID: "anthropic", modelID: "claude-opus-5-5" }, finish: "error", error: { type: "provider.auth", status: 403 } },
  })
})

test("recovers a file-backed pending create with the caller-supplied OpenCode session id", async () => {
  const root = await mkdtemp(join(process.cwd(), "local/tmp/hermes-mcp-recovery-"))
  const file = join(root, "delegation.json")
  const sessions = new Map<string, CommanderSession>()
  let creates = 0
  const gateway: OpenCodeCommanderGateway = {
    listProjects: async () => [{ id: "project-1", name: "digitaltwin", directory: "/srv/digitaltwin" }],
    createSession: async ({ id }) => {
      creates += 1
      const existing = sessions.get(id)
      if (existing) return existing
      const created = { id, projectID: "project-1" }
      sessions.set(id, created)
      return created
    },
    prompt: async (input) => ({ id: input.messageID, type: "user", text: input.text, metadata: input.metadata }),
    waitSession: async () => undefined,
    readSession: async (id) => {
      const result = sessions.get(id)
      if (!result) throw new Error("not found")
      return result
    },
    readMessages: async () => [],
  }
  const raw = new FileDelegationStore(file)
  let failFinalWrite = true
  const interrupted: DelegationStore = {
    read: () => raw.read(),
    write: async (state) => {
      if (state.decisions && Object.keys(state.decisions).length > 0 && failFinalWrite) {
        failFinalWrite = false
        throw new Error("simulated process interruption")
      }
      await raw.write(state)
    },
    exclusive: (work) => raw.exclusive(work),
  }
  try {
    const first = new CommanderDelegation(gateway, interrupted, "hermes-profile-local")
    await assert.rejects(first.create({ projectID: "project-1", requestID: "recover-1", text: "Recover me." }), /simulated process interruption/)
    const pending = await raw.read()
    assert.equal(Object.keys(pending.pending).length, 1)
    const restored = new CommanderDelegation(gateway, raw, "hermes-profile-local")
    const result = await restored.create({ projectID: "project-1", requestID: "recover-1", text: "Recover me." })
    assert.match(String(result.session_id), /^ses_hermes_commander_[a-f0-9]{64}$/)
    assert.equal(sessions.size, 1)
    assert.equal(creates, 2)
    assert.equal(Object.keys((await raw.read()).pending).length, 0)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test("serializes concurrent file-backed delegations so neither decision is lost", async () => {
  const root = await mkdtemp(join(process.cwd(), "local/tmp/hermes-mcp-lock-"))
  const file = join(root, "delegation.json")
  const sessions = new Map<string, CommanderSession>()
  const gateway: OpenCodeCommanderGateway = {
    listProjects: async () => [{ id: "project-1", name: "digitaltwin", directory: "/srv/digitaltwin" }],
    createSession: async ({ id }) => {
      const session = { id, projectID: "project-1" }
      sessions.set(id, session)
      return session
    },
    prompt: async (input) => ({ id: input.messageID, type: "user", text: input.text, metadata: input.metadata }),
    waitSession: async () => undefined,
    readSession: async (id) => {
      const result = sessions.get(id)
      if (!result) throw new Error("not found")
      return result
    },
    readMessages: async () => [],
  }
  try {
    const first = new CommanderDelegation(gateway, new FileDelegationStore(file), "hermes-profile-local")
    const second = new CommanderDelegation(gateway, new FileDelegationStore(file), "hermes-profile-local")
    await Promise.all([
      first.create({ projectID: "project-1", requestID: "concurrent-1", text: "First." }),
      second.create({ projectID: "project-1", requestID: "concurrent-2", text: "Second." }),
    ])
    const state = await new FileDelegationStore(file).read()
    assert.equal(Object.keys(state.decisions).length, 2)
    assert.equal(Object.keys(state.requests).length, 2)
    assert.equal(Object.keys(state.pending).length, 0)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test("recovers a lock left without an owner by a process that died during lock bootstrap", async () => {
  const root = await mkdtemp(join(process.cwd(), "local/tmp/hermes-mcp-orphaned-lock-"))
  const file = join(root, "delegation.json")
  try {
    await mkdir(`${file}.lock`, { recursive: true })
    const store = new FileDelegationStore(file, 0)
    let entered = false
    await store.exclusive(async () => { entered = true })
    assert.equal(entered, true)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})
