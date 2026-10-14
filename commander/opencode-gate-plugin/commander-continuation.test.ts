import assert from "node:assert/strict"
import test from "node:test"
import continuation from "./commander-continuation.ts"

function fixture() {
  const storage = new Map<string, unknown>(); const tools = new Map<string, any>(); const hooks = new Map<string, any>(); const prompts: any[] = []
  const context = { location: { project: { id: "project-1" } }, storage: { get: async (key: string) => storage.get(key), set: async (key: string, value: unknown) => storage.set(key, value) }, tool: { transform: async (callback: any) => callback({ add: (tool: any) => tools.set(tool.name, tool) }), hook: async (name: string, callback: any) => { hooks.set(name, callback); return { dispose() {} } } }, session: { prompt: async (input: any) => { prompts.push(input); return { id: input.id, sessionID: input.sessionID, type: "user", payload: { text: input.text, metadata: input.metadata } } } } }
  return { context, storage, tools, hooks, prompts }
}
async function bind(f: ReturnType<typeof fixture>, call = "call_child", parent = "ses_commander", child = "ses_child") {
  await f.hooks.get("execute.after")({ tool: "subagent", status: "completed", id: call, sessionID: parent, messageID: "msg_parent", result: { metadata: { sessionID: child } } })
  return `subagent-${call}`
}

test("binds the actual native child result and only its parent may continue", async () => {
  const f = fixture(); await continuation.setup(f.context as never); const id = await bind(f)
  const record = f.storage.get(`digitaltwin.commander.decision.${id}`) as any
  assert.deepEqual(record, { parent: "ses_commander", parentMessage: "msg_parent", child: "ses_child", project: "project-1", requests: {} })
  const tool = f.tools.get("commander_continue_agent")
  assert.equal((await tool.execute({ decision_id: id, request_id: "request-1", text: "Continue." }, { sessionID: "ses_other" })).content, "Commander follow-up is not authorized for this session.")
  assert.equal((await tool.execute({ decision_id: id, request_id: "request-1", text: "Continue." }, { sessionID: "ses_commander" })).content, `Continued Commander decision ${id}.`)
  assert.equal(f.prompts[0].sessionID, "ses_child")
})

test("persists binding across setup and serializes changed-body retries", async () => {
  const first = fixture(); await continuation.setup(first.context as never); const id = await bind(first, "call_restart")
  const second = fixture(); for (const [key, value] of first.storage) second.storage.set(key, value); await continuation.setup(second.context as never)
  const tool = second.tools.get("commander_continue_agent")
  const [one, two] = await Promise.all([
    tool.execute({ decision_id: id, request_id: "request-2", text: "Body one" }, { sessionID: "ses_commander" }),
    tool.execute({ decision_id: id, request_id: "request-2", text: "Body two" }, { sessionID: "ses_commander" }),
  ])
  assert.deepEqual([one.content, two.content].sort(), [`Commander follow-up conflicts with its original body.`, `Continued Commander decision ${id}.`].sort())
  assert.equal(second.prompts.length, 1)
})

test("rejects an already-admitted mismatched message", async () => {
  const f = fixture(); await continuation.setup(f.context as never); const id = await bind(f, "call_mismatch")
  f.context.session.prompt = async (input: any) => ({ id: input.id, sessionID: input.sessionID, type: "user", payload: { text: "different", metadata: input.metadata } })
  const tool = f.tools.get("commander_continue_agent")
  assert.equal((await tool.execute({ decision_id: id, request_id: "request-3", text: "Expected" }, { sessionID: "ses_commander" })).content, "Commander follow-up admission conflicts with the existing message.")
})
