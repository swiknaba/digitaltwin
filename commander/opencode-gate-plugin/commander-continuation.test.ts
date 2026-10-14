import assert from "node:assert/strict"
import test from "node:test"
import continuation from "./commander-continuation.ts"

type Tool = Readonly<{
  name: string
  execute: (input: Record<string, string>, context?: Record<string, string>) => Promise<Readonly<{ content: string }>>
}>

function setup() {
  const storage = new Map<string, unknown>()
  const tools = new Map<string, Tool>()
  const prompts: Array<Record<string, unknown>> = []
  const context = {
    location: { project: { id: "project-commander" } },
    storage: {
      get: async (key: string) => storage.get(key),
      set: async (key: string, value: unknown) => storage.set(key, value),
    },
    tool: {
      transform: async (callback: (editor: { add: (tool: Tool) => void }) => void) => callback({ add: (tool) => tools.set(tool.name, tool) }),
    },
    session: { prompt: async (input: Record<string, unknown>) => prompts.push(input) },
  }
  return { context, prompts, storage, tools }
}

test("persists trusted provenance and resumes that exact OpenCode session", async () => {
  const first = setup()
  await continuation.setup(first.context as never)
  const start = first.tools.get("commander_record_agent_session")
  const followUp = first.tools.get("commander_continue_agent")
  assert.ok(start)
  assert.ok(followUp)

  const commanderSessionID = "ses_commander"
  await start.execute(
    { decision_id: "decision-1", session_id: commanderSessionID },
    { sessionID: "ses_child_agent", messageID: "msg_child_origin" },
  )
  const expectedProvenance = {
    runtimeId: "opencode:server",
    projectId: "project-commander",
    sessionId: "ses_child_agent",
    messageId: "msg_child_origin",
    requests: {},
  }
  const recorded = first.storage.get("digitaltwin.commander.decision.decision-1")
  assert.deepEqual(recorded, expectedProvenance)
  assert.notEqual(expectedProvenance.sessionId, commanderSessionID)

  await followUp.execute({ decision_id: "decision-1", request_id: "request-1", text: "Continue safely." })
  assert.equal(first.prompts.length, 1)
  assert.match(String(first.prompts[0].sessionID), /^ses_child_agent$/)
  assert.match(String(first.prompts[0].id), /^msg_commander_[a-f0-9]{64}$/)
  assert.equal(first.prompts[0].text, "Continue safely.")
  assert.deepEqual(first.prompts[0].metadata, {
    fromCommander: true,
    commanderRequestDigest: "7628cfc6a2a30ad4f00ceffa33dfc563fe60146b9508b30bf9fec129e1ac9f58",
  })
  assert.equal(first.prompts[0].resume, true)

  const second = setup()
  for (const [key, value] of first.storage) second.storage.set(key, value)
  await continuation.setup(second.context as never)
  const retry = second.tools.get("commander_continue_agent")
  assert.ok(retry)
  await retry.execute({ decision_id: "decision-1", request_id: "request-1", text: "Continue safely." })
  assert.equal(second.prompts.length, 1)
  assert.equal(second.prompts[0].id, first.prompts[0].id)
  const conflict = await retry.execute({ decision_id: "decision-1", request_id: "request-1", text: "Different body." })
  assert.equal(conflict.content, "Commander follow-up conflicts with its original body.")
  assert.equal(second.prompts.length, 1)
})
