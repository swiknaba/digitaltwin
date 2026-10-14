import { createHash } from "node:crypto"
import { Plugin } from "@opencode/plugin"
import { Schema } from "effect"

const prefix = "digitaltwin.commander.decision."
type Decision = Readonly<{ parent: string; parentMessage: string; child: string; project: string; requests: Readonly<Record<string, string>> }>

export default Plugin.define({
  id: "digitaltwin-commander-continuation",
  async setup(context) {
    const locks = new Map<string, Promise<void>>()
    await context.tool.hook("execute.after", async (event) => {
      if (event.tool !== "subagent" || event.status !== "completed") return
      const child = childSession(event.result)
      if (!child) return
      const decisionID = `subagent-${event.id}`
      const key = prefix + decisionID
      const next: Decision = { parent: event.sessionID, parentMessage: event.messageID, child, project: context.location.project.id, requests: {} }
      await exclusive(locks, key, async () => {
        const previous = decode(await context.storage.get(key))
        if (!previous) await context.storage.set(key, next)
      })
    })
    await context.tool.transform((editor) => editor.add({
      name: "commander_continue_agent",
      description: "Resume the child agent from this Commander session's native subagent call.",
      input: Schema.Struct({ decision_id: Schema.String, request_id: Schema.String, text: Schema.String }),
      options: { codemode: false },
      async execute(input, tool) {
        if (!id(input.decision_id) || !id(input.request_id) || !input.text.trim()) return { content: "Invalid Commander follow-up." }
        const key = prefix + input.decision_id
        return exclusive(locks, `${key}:${input.request_id}`, async () => {
          const decision = decode(await context.storage.get(key))
          if (!decision) return { content: "Commander decision was not found." }
          if (decision.parent !== tool.sessionID) return { content: "Commander follow-up is not authorized for this session." }
          const digest = hash(input.text); const old = decision.requests[input.request_id]
          if (old && old !== digest) return { content: "Commander follow-up conflicts with its original body." }
          const message = "msg_commander_" + hash([decision.project, decision.child, input.request_id].join("\n"))
          const metadata = { fromCommander: true as const, commanderRequestDigest: digest }
          const admitted = await context.session.prompt({ sessionID: decision.child, id: message, text: input.text, metadata, resume: true })
          if (!admission(admitted, decision.child, message, input.text, metadata)) return { content: "Commander follow-up admission conflicts with the existing message." }
          if (!old) await context.storage.set(key, { ...decision, requests: { ...decision.requests, [input.request_id]: digest } })
          return { content: `Continued Commander decision ${input.decision_id}.` }
        })
      },
    }))
  },
})

function childSession(result: unknown): string | undefined { if (!object(result) || !object(result.metadata) || typeof result.metadata.sessionID !== "string") return; return result.metadata.sessionID }
function admission(value: unknown, session: string, id: string, text: string, metadata: Readonly<{ fromCommander: true; commanderRequestDigest: string }>) { return object(value) && value.sessionID === session && value.id === id && value.type === "user" && object(value.payload) && value.payload.text === text && object(value.payload.metadata) && value.payload.metadata.fromCommander === true && value.payload.metadata.commanderRequestDigest === metadata.commanderRequestDigest }
function decode(value: unknown): Decision | undefined { if (!object(value) || typeof value.parent !== "string" || typeof value.parentMessage !== "string" || typeof value.child !== "string" || typeof value.project !== "string" || !object(value.requests)) return; const requests: Record<string, string> = {}; for (const [key, digest] of Object.entries(value.requests)) { if (!id(key) || typeof digest !== "string" || !/^[a-f0-9]{64}$/.test(digest)) return; requests[key] = digest } return { parent: value.parent, parentMessage: value.parentMessage, child: value.child, project: value.project, requests } }
function id(value: string) { return /^[a-z0-9][a-z0-9_-]{0,255}$/i.test(value) }
function hash(value: string) { return createHash("sha256").update(value, "utf8").digest("hex") }
function object(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value) }
async function exclusive<T>(locks: Map<string, Promise<void>>, key: string, operation: () => Promise<T>): Promise<T> { const previous = locks.get(key) ?? Promise.resolve(); let release = () => {}; const current = new Promise<void>((resolve) => { release = resolve }); locks.set(key, previous.then(() => current)); await previous; try { return await operation() } finally { release(); if (locks.get(key) === current) locks.delete(key) } }
