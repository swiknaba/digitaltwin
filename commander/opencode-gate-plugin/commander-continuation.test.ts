import assert from "node:assert/strict"
import test from "node:test"
import continuation from "./commander-continuation.ts"

function fixture() {
  const storage = new Map<string, unknown>(); const tools = new Map<string, any>(); const hooks = new Map<string, any>(); const prompts: any[] = []; const native: any[] = []
  const sessions: Record<string, any> = {
    ses_commander: { id: "ses_commander", projectID: "project-1" },
    ses_child: { id: "ses_child", parentID: "ses_commander", projectID: "project-1" },
  }
  const context = {
    storage: { get: async (key: string) => storage.get(key), set: async (key: string, value: unknown) => storage.set(key, value) },
    tool: { transform: async (callback: any) => callback({ add: (tool: any) => tools.set(tool.name, tool) }), hook: async (name: string, callback: any) => { hooks.set(name, callback); return { dispose() {} } } },
    session: {
      get: async ({ sessionID }: any) => { if (!sessions[sessionID]) throw new Error("missing"); return sessions[sessionID] },
      context: async () => native,
      prompt: async (input: any) => { prompts.push(input); return { id: input.id, sessionID: input.sessionID, type: "user", payload: { text: input.text, metadata: input.metadata } } },
    },
    project: {
      list: async () => [{ id: "project-1", canonical: "/srv/digitaltwin", name: "digitaltwin" }],
    },
  }
  return { context, storage, tools, hooks, prompts, native, sessions }
}

async function bind(f: ReturnType<typeof fixture>, call = "opaque/provider:call", parent = "ses_commander", child = "ses_child", state = "running") {
  const event: any = { tool: "subagent", status: "completed", id: call, sessionID: parent, messageID: "msg_parent", result: { content: [{ type: "text", text: "Native subagent result" }], metadata: { sessionID: child, status: state } } }
  await f.hooks.get("execute.after")(event)
  const decision = event.result.metadata.commanderDecisionID
  f.native.push({ type: "assistant", content: [{ type: "tool", name: "subagent", state: { status: "completed", metadata: event.result.metadata } }] })
  return { decision, event }
}

test("binds the actual native child launch, exposes its reference, and only its parent may continue", async () => {
  const f = fixture(); await continuation.setup(f.context as never); const { decision, event } = await bind(f)
  assert.match(decision, /^subagent-[a-f0-9]{64}$/)
  assert.deepEqual(event.result.content, [
    { type: "text", text: "Native subagent result" },
    { type: "text", text: `Commander follow-up reference: ${decision}` },
  ])
  const record = f.storage.get(`digitaltwin.commander.decision.${decision}`) as any
  assert.deepEqual(record, { parent: "ses_commander", parentMessage: "msg_parent", child: "ses_child", project: "project-1", requests: {} })
  const tool = f.tools.get("commander_continue_agent")
  assert.equal((await tool.execute({ decision_id: decision, request_id: "request-1", text: "Continue." }, { sessionID: "ses_other" })).content, "Commander follow-up is not authorized for this session.")
  assert.equal((await tool.execute({ decision_id: decision, request_id: "request-1", text: "Continue." }, { sessionID: "ses_commander" })).content, `Continued Commander decision ${decision}.`)
  assert.equal(f.prompts[0].sessionID, "ses_child")
})

test("creates a project session with a durable exact-session follow-up reference", async () => {
  const f = fixture(); await continuation.setup(f.context as never)
  const list = f.tools.get("commander_list_projects")
  assert.deepEqual(JSON.parse((await list.execute({}, { sessionID: "ses_commander" })).content), [
    { id: "project-1", name: "digitaltwin", directory: "/srv/digitaltwin" },
  ])
  let created: any
  f.context.session.create = async (input: any) => {
    created = input
    f.sessions.ses_digitaltwin = { id: "ses_digitaltwin", projectID: "project-1" }
    return { id: "ses_digitaltwin" }
  }
  const create = f.tools.get("commander_create_project_session")
  const result = JSON.parse((await create.execute({ project_id: "project-1", request_id: "ping-1", text: "ping" }, { sessionID: "ses_commander", messageID: "msg_create", id: "call_create" })).content)
  assert.deepEqual(created, { location: { directory: "/srv/digitaltwin" } })
  assert.deepEqual(result, { project_id: "project-1", session_id: "ses_digitaltwin", message_id: result.message_id, request_id: "ping-1", decision_id: result.decision_id })
  assert.match(result.message_id, /^msg_commander_project_[a-f0-9]{64}$/)
  assert.match(result.decision_id, /^project-session-[a-f0-9]{64}$/)
  assert.deepEqual(f.prompts.at(-1), {
    sessionID: "ses_digitaltwin", id: result.message_id, text: "Commander-directed work:\n\nping", resume: true,
    metadata: { fromCommander: true, commanderProjectID: "project-1", commanderRequestID: "ping-1" },
  })
  const followUp = f.tools.get("commander_continue_agent")
  assert.equal((await followUp.execute({ decision_id: result.decision_id, request_id: "follow-up-1", text: "Continue." }, { sessionID: "ses_commander" })).content, `Continued Commander decision ${result.decision_id}.`)
  assert.deepEqual(f.prompts.at(-1), {
    sessionID: "ses_digitaltwin", id: f.prompts.at(-1).id, text: "Commander-directed work:\n\nContinue.", resume: true,
    metadata: { fromCommander: true, commanderRequestDigest: "f3daf2941865055833e9db4c9bab5d1280281952bb1699514a28ee4c67256573" },
  })
  assert.equal((await followUp.execute({ decision_id: result.decision_id, request_id: "follow-up-2", text: "Wrong parent." }, { sessionID: "ses_other" })).content, "Commander follow-up is not authorized for this session.")
  const restarted = fixture(); restarted.sessions.ses_digitaltwin = { id: "ses_digitaltwin", projectID: "project-1" }
  for (const [key, value] of f.storage) restarted.storage.set(key, value)
  await continuation.setup(restarted.context as never)
  const restartedFollowUp = restarted.tools.get("commander_continue_agent")
  assert.equal((await restartedFollowUp.execute({ decision_id: result.decision_id, request_id: "follow-up-after-restart", text: "Recovered." }, { sessionID: "ses_commander" })).content, `Continued Commander decision ${result.decision_id}.`)
  assert.equal(restarted.prompts.at(-1).sessionID, "ses_digitaltwin")
  f.native.push({ type: "assistant", text: "Completed the requested work." })
  const read = f.tools.get("commander_read_agent")
  assert.deepEqual(JSON.parse((await read.execute({ decision_id: result.decision_id }, { sessionID: "ses_commander" })).content), {
    session_id: "ses_digitaltwin", project_id: "project-1", latest_result: { type: "assistant", text: "Completed the requested work." },
  })
  assert.equal((await read.execute({ decision_id: result.decision_id }, { sessionID: "ses_other" })).content, "Commander follow-up is not authorized for this session.")
})

test("reuses a direct project-session reference across a repeated create request", async () => {
  const f = fixture(); await continuation.setup(f.context as never)
  let created = 0
  f.context.session.create = async () => {
    created += 1
    f.sessions.ses_digitaltwin = { id: "ses_digitaltwin", projectID: "project-1" }
    return { id: "ses_digitaltwin" }
  }
  const create = f.tools.get("commander_create_project_session")
  const context = { sessionID: "ses_commander", messageID: "msg_create", id: "call_create" }
  const first = JSON.parse((await create.execute({ project_id: "project-1", request_id: "ping-1", text: "ping" }, context)).content)
  const retry = JSON.parse((await create.execute({ project_id: "project-1", request_id: "ping-1", text: "ping" }, context)).content)
  assert.equal(created, 1)
  assert.deepEqual(retry, first)
  assert.equal(f.prompts.length, 2)
  assert.equal((await create.execute({ project_id: "project-1", request_id: "ping-1", text: "different" }, context)).content, "Commander project session request conflicts with its original body.")
})

test("recovers a referenced decision from the persisted native parent result after restart", async () => {
  const first = fixture(); await continuation.setup(first.context as never); const { decision } = await bind(first, "call_restart", "ses_commander", "ses_child", "completed")
  const second = fixture(); second.native.push(...first.native); await continuation.setup(second.context as never)
  const tool = second.tools.get("commander_continue_agent")
  assert.equal((await tool.execute({ decision_id: decision, request_id: "request-2", text: "Recovered body" }, { sessionID: "ses_commander" })).content, `Continued Commander decision ${decision}.`)
  assert.equal(second.prompts.length, 1)
  assert.ok(second.storage.has(`digitaltwin.commander.decision.${decision}`))
})

test("serializes every repeated decision follow-up without losing independent request IDs", async () => {
  const f = fixture(); await continuation.setup(f.context as never); const { decision } = await bind(f)
  const tool = f.tools.get("commander_continue_agent")
  await Promise.all([
    tool.execute({ decision_id: decision, request_id: "request-a", text: "Body one" }, { sessionID: "ses_commander" }),
    tool.execute({ decision_id: decision, request_id: "request-b", text: "Body two" }, { sessionID: "ses_commander" }),
  ])
  const record = f.storage.get(`digitaltwin.commander.decision.${decision}`) as any
  assert.deepEqual(Object.keys(record.requests).sort(), ["request-a", "request-b"])
  assert.equal(f.prompts.length, 2)
})

test("rejects a mismatched native project and an already-admitted mismatched prompt", async () => {
  const f = fixture(); f.sessions.ses_child.projectID = "project-other"; await continuation.setup(f.context as never); const { event } = await bind(f)
  assert.equal(event.result.metadata.commanderDecisionID, undefined)
  f.sessions.ses_child.projectID = "project-1"
  const bound = await bind(f, "call_mismatch")
  f.context.session.prompt = async (input: any) => ({ id: input.id, sessionID: input.sessionID, type: "user", payload: { text: "different", metadata: input.metadata } })
  const tool = f.tools.get("commander_continue_agent")
  assert.equal((await tool.execute({ decision_id: bound.decision, request_id: "request-3", text: "Expected" }, { sessionID: "ses_commander" })).content, "Commander follow-up admission conflicts with the existing message.")
})
