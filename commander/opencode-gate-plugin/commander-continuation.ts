import { createHash } from "node:crypto"
import { Plugin } from "@opencode/plugin"
import { Schema } from "effect"

const prefix = "digitaltwin.commander.decision."

type Decision = Readonly<{
  runtimeId: string
  projectId: string
  sessionId: string
  messageId: string
  requests: Readonly<Record<string, string>>
}>

/**
 * Standard v2.0.27 server plugin. It records provenance from OpenCode's trusted
 * tool context, never from a renderer or tool argument, and resumes only that
 * exact session through context.session.prompt.
 */
export default Plugin.define({
  id: "digitaltwin-commander-continuation",
  async setup(context) {
    await context.tool.transform((editor) => {
      editor.add({
        name: "commander_record_agent_session",
        description: "Record this running Commander-started child agent session for later Commander follow-up.",
        input: Schema.Struct({ decision_id: Schema.String }),
        options: { codemode: false },
        async execute(input, tool) {
          if (!decisionID(input.decision_id)) return { content: "Invalid Commander decision id." }
          const next: Decision = {
            runtimeId: "opencode:server",
            projectId: context.location.project.id,
            sessionId: tool.sessionID,
            messageId: tool.messageID,
            requests: {},
          }
          const key = prefix + input.decision_id
          const existing = decodeDecision(await context.storage.get(key))
          if (existing && !sameOrigin(existing, next)) return { content: "Commander decision id conflicts with an existing session." }
          if (!existing) await context.storage.set(key, next)
          return { content: `Recorded Commander decision ${input.decision_id}.` }
        },
      })
      editor.add({
        name: "commander_continue_agent",
        description: "Resume the exact agent session previously recorded by Commander.",
        input: Schema.Struct({ decision_id: Schema.String, request_id: Schema.String, text: Schema.String }),
        options: { codemode: false },
        async execute(input) {
          if (!decisionID(input.decision_id) || !requestID(input.request_id) || !input.text.trim()) return { content: "Invalid Commander follow-up." }
          const key = prefix + input.decision_id
          const decision = decodeDecision(await context.storage.get(key))
          if (!decision) return { content: "Commander decision was not found." }
          const digest = createHash("sha256").update(input.text, "utf8").digest("hex")
          const recorded = decision.requests[input.request_id]
          if (recorded && recorded !== digest) return { content: "Commander follow-up conflicts with its original body." }
          const inputId = "msg_commander_" + createHash("sha256").update([decision.runtimeId, decision.projectId, decision.sessionId, decision.messageId, input.request_id].join("\n"), "utf8").digest("hex")
          if (!recorded) {
            await context.storage.set(key, { ...decision, requests: { ...decision.requests, [input.request_id]: digest } })
          }
          await context.session.prompt({
            sessionID: decision.sessionId,
            id: inputId,
            text: input.text,
            metadata: { fromCommander: true, commanderRequestDigest: digest },
            resume: true,
          })
          return { content: `Continued Commander decision ${input.decision_id}.` }
        },
      })
    })
  },
})

function decisionID(value: string): boolean {
  return /^[a-z0-9][a-z0-9_-]{0,127}$/i.test(value)
}

function requestID(value: string): boolean {
  return value.length > 0 && value.length <= 256
}

function decodeDecision(value: unknown): Decision | undefined {
  if (!record(value) || typeof value.runtimeId !== "string" || typeof value.projectId !== "string" || typeof value.sessionId !== "string" || typeof value.messageId !== "string" || !record(value.requests)) return undefined
  const requests: Record<string, string> = {}
  for (const [requestId, digest] of Object.entries(value.requests)) {
    if (!requestID(requestId) || typeof digest !== "string" || !/^[a-f0-9]{64}$/.test(digest)) return undefined
    requests[requestId] = digest
  }
  return {
    runtimeId: value.runtimeId,
    projectId: value.projectId,
    sessionId: value.sessionId,
    messageId: value.messageId,
    requests,
  }
}

function sameOrigin(left: Decision, right: Decision): boolean {
  return left.runtimeId === right.runtimeId && left.projectId === right.projectId && left.sessionId === right.sessionId && left.messageId === right.messageId
}

function record(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}
