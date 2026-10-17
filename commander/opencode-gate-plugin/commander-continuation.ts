import { createHash } from "node:crypto"
import { Plugin } from "@opencode/plugin"
import type { Tool } from "@opencode/schema/tool"
import { Schema } from "effect"

const prefix = "digitaltwin.commander.decision."
const projectRequestPrefix = "digitaltwin.commander.project-request."
const projectSessionPrefix = "digitaltwin.commander.project-session."
type Decision = Readonly<{ parent: string; parentMessage: string; child: string; project: string; requests: Readonly<Record<string, string>> }>
type ProjectRequest = Readonly<{ parent: string; project: string; requestDigest: string; decisionID: string }>

export default Plugin.define({
  id: "digitaltwin-commander-continuation",
  async setup(context) {
    const locks = new Map<string, Promise<void>>()

    const validate = async (value: Readonly<{ parent: string; parentMessage: string; child: string }>): Promise<Decision | undefined> => {
      try {
        const [parent, child] = await Promise.all([
          context.session.get({ sessionID: value.parent }),
          context.session.get({ sessionID: value.child }),
        ])
        if (child.parentID !== parent.id || parent.id !== value.parent || child.id !== value.child || child.projectID !== parent.projectID) return
        return { ...value, project: parent.projectID, requests: {} }
      } catch {
        return
      }
    }

    const validateProjectSession = async (value: Readonly<{ parent: string; parentMessage: string; child: string; project: string }>): Promise<Decision | undefined> => {
      try {
        const [parent, child] = await Promise.all([
          context.session.get({ sessionID: value.parent }),
          context.session.get({ sessionID: value.child }),
        ])
        if (parent.id !== value.parent || child.id !== value.child || child.projectID !== value.project) return
        return { ...value, requests: {} }
      } catch {
        return
      }
    }

    const recover = async (decisionID: string, parent: string): Promise<Decision | undefined> => {
      const key = prefix + decisionID
      const stored = decode(await context.storage.get(key))
      if (stored) return stored
      let messages: unknown
      try {
        messages = await context.session.context({ sessionID: parent })
      } catch {
        return
      }
      const candidate = nativeDecision(messages, decisionID, parent)
      if (!candidate) return
      const restored = await validate(candidate)
      if (!restored) return
      await context.storage.set(key, restored)
      return restored
    }

    const recoverProjectSession = async (sessionID: string, parent: string): Promise<Readonly<{ decisionID: string; decision: Decision }> | undefined> => {
      const referenceKey = projectSessionPrefix + projectSessionReferenceID(parent, sessionID)
      const remembered = await context.storage.get(referenceKey)
      if (typeof remembered === "string" && decisionID(remembered)) {
        const decision = await recover(remembered, parent)
        if (decision) return { decisionID: remembered, decision }
      }
      let parentMessages: unknown
      try {
        parentMessages = await context.session.context({ sessionID: parent })
      } catch {
        return
      }
      const candidate = historicalProjectSession(parentMessages, parent, sessionID)
      if (!candidate) return
      const decision = await validateProjectSession(candidate)
      if (!decision) return
      let childMessages: unknown
      try {
        childMessages = await context.session.context({ sessionID })
      } catch {
        return
      }
      if (!createdMessage(childMessages, candidate.messageID, candidate.project, candidate.requestID)) return
      const resolvedID = projectSessionDecisionIDFor(parent, candidate.parentMessage, candidate.callID, sessionID)
      const key = prefix + resolvedID
      await exclusive(locks, key, async () => {
        const previous = decode(await context.storage.get(key))
        if (!previous) await context.storage.set(key, decision)
      })
      await context.storage.set(referenceKey, resolvedID)
      return { decisionID: resolvedID, decision }
    }

    await context.tool.hook("execute.after", async (event) => {
      if (event.tool !== "subagent" || event.status !== "completed") return
      const child = childSession(event.result)
      if (!child) return
      const decisionID = decisionIDFor(event.sessionID, event.messageID, event.id, child)
      const next = await validate({ parent: event.sessionID, parentMessage: event.messageID, child })
      if (!next) return
      event.result = referenced(event.result, decisionID, event.messageID)
      const key = prefix + decisionID
      await exclusive(locks, key, async () => {
        const previous = decode(await context.storage.get(key))
        if (!previous) await context.storage.set(key, next)
      })
    })

    await context.tool.transform((editor) => editor.add({
      name: "commander_list_projects",
      description: "List the existing OpenCode projects Commander may target for a new normal session.",
      input: Schema.Struct({}),
      options: { codemode: false },
      async execute() {
        const projects = await context.project.list()
        return {
          content: JSON.stringify(
            projects.map((project) => ({ id: project.id, name: project.name ?? project.canonical.split("/").at(-1) ?? project.canonical, directory: project.canonical })),
          ),
        }
      },
    }))

    await context.tool.transform((editor) => editor.add({
      name: "commander_create_project_session",
      description: "Create a normal project session, post the supplied prompt, and return its opaque Commander follow-up reference.",
      input: Schema.Struct({ project_id: Schema.String, request_id: Schema.String, text: Schema.String }),
      options: { codemode: false },
      async execute(input, tool) {
        if (!requestID(input.request_id) || !input.text.trim()) return { content: "Invalid Commander project session request." }
        const project = (await context.project.list()).find((item) => item.id === input.project_id)
        if (!project) return { content: "Commander project was not found." }
        const key = projectRequestPrefix + projectRequestID(tool.sessionID, project.id, input.request_id)
        const digest = hash(input.text)
        return exclusive(locks, key, async () => {
          const previous = decodeProjectRequest(await context.storage.get(key))
          if (previous) {
            if (previous.parent !== tool.sessionID || previous.project !== project.id || previous.requestDigest !== digest) return { content: "Commander project session request conflicts with its original body." }
            const decision = decode(await context.storage.get(prefix + previous.decisionID))
            if (!decision || decision.parent !== tool.sessionID || decision.project !== project.id) return { content: "Commander project session reference could not be recovered." }
            const message = projectMessageIDFor(project.id, input.request_id)
            const metadata = { fromCommander: true as const, commanderProjectID: project.id, commanderRequestID: input.request_id }
            const text = commanderAgentText(input.text)
            const admitted = await context.session.prompt({ sessionID: decision.child, id: message, text, metadata, resume: true })
            if (!admission(admitted, decision.child, message, text, metadata)) return { content: "Commander project session admission conflicts with the existing message." }
            return projectSessionResult(project.id, decision.child, input.request_id, previous.decisionID)
          }

          const session = await context.session.create({ location: { directory: project.canonical } })
          const decisionID = projectSessionDecisionIDFor(tool.sessionID, tool.messageID, tool.id, session.id)
          const decision = await validateProjectSession({ parent: tool.sessionID, parentMessage: tool.messageID, child: session.id, project: project.id })
          if (!decision) return { content: "Commander project session could not be verified." }
          await context.storage.set(prefix + decisionID, decision)
          await context.storage.set(key, { parent: tool.sessionID, project: project.id, requestDigest: digest, decisionID })

          const message = projectMessageIDFor(project.id, input.request_id)
          const metadata = { fromCommander: true as const, commanderProjectID: project.id, commanderRequestID: input.request_id }
          const text = commanderAgentText(input.text)
          const admitted = await context.session.prompt({ sessionID: session.id, id: message, text, metadata, resume: true })
          if (!admission(admitted, session.id, message, text, metadata)) return { content: "Commander project session admission conflicts with the existing message." }
          return projectSessionResult(project.id, session.id, input.request_id, decisionID)
        })
      },
    }))

    await context.tool.transform((editor) => editor.add({
      name: "commander_continue_agent",
      description: "Resume an exact Commander-created target. Use decision_id from a current create result, or session_id for an older create result that returned only session_id and message_id. Never invent either value.",
      input: Schema.Struct({ decision_id: Schema.optional(Schema.String), session_id: Schema.optional(Schema.String), request_id: Schema.String, text: Schema.String }),
      options: { codemode: false },
      async execute(input, tool) {
        const target = followUpTarget(input.decision_id, input.session_id)
        if (!target || !requestID(input.request_id) || !input.text.trim()) return { content: "Invalid Commander follow-up. Use exactly one decision_id or session_id from Commander-created work." }
        const targetKey = target.kind === "decision" ? prefix + target.value : `${prefix}session.${target.value}`
        return exclusive(locks, targetKey, async () => {
          const resolved = target.kind === "decision" ? await recover(target.value, tool.sessionID).then((decision) => decision ? { decisionID: target.value, decision } : undefined) : await recoverProjectSession(target.value, tool.sessionID)
          if (!resolved) return { content: "Commander decision was not found." }
          const key = prefix + resolved.decisionID
          const decision = resolved.decision
          if (decision.parent !== tool.sessionID) return { content: "Commander follow-up is not authorized for this session." }
          const digest = hash(input.text); const old = decision.requests[input.request_id]
          if (old && old !== digest) return { content: "Commander follow-up conflicts with its original body." }
          const message = "msg_commander_" + hash([decision.project, decision.child, input.request_id].join("\n"))
          const metadata = { fromCommander: true as const, commanderRequestDigest: digest }
          const text = commanderAgentText(input.text)
          const admitted = await context.session.prompt({ sessionID: decision.child, id: message, text, metadata, resume: true })
          if (!admission(admitted, decision.child, message, text, metadata)) return { content: "Commander follow-up admission conflicts with the existing message." }
          if (!old) await context.storage.set(key, { ...decision, requests: { ...decision.requests, [input.request_id]: digest } })
          return { content: `Continued Commander decision ${resolved.decisionID}.` }
        })
      },
    }))

    await context.tool.transform((editor) => editor.add({
      name: "commander_read_agent",
      description: "Read the current session and latest result without sending a prompt. Use decision_id from a current create result, or session_id for an older create result that returned only session_id and message_id. Never invent either value.",
      input: Schema.Struct({ decision_id: Schema.optional(Schema.String), session_id: Schema.optional(Schema.String) }),
      options: { codemode: false },
      async execute(input, tool) {
        const target = followUpTarget(input.decision_id, input.session_id)
        if (!target) return { content: "Invalid Commander result reference. Use exactly one decision_id or session_id from Commander-created work." }
        const targetKey = target.kind === "decision" ? prefix + target.value : `${prefix}session.${target.value}`
        return exclusive(locks, targetKey, async () => {
          const resolved = target.kind === "decision" ? await recover(target.value, tool.sessionID).then((decision) => decision ? { decisionID: target.value, decision } : undefined) : await recoverProjectSession(target.value, tool.sessionID)
          if (!resolved) return { content: "Commander decision was not found." }
          const decision = resolved.decision
          if (decision.parent !== tool.sessionID) return { content: "Commander follow-up is not authorized for this session." }
          try {
            const [session, messages] = await Promise.all([
              context.session.get({ sessionID: decision.child }),
              context.session.context({ sessionID: decision.child }),
            ])
            return { content: JSON.stringify({ session_id: session.id, project_id: session.projectID, latest_result: latestAssistant(messages) }) }
          } catch {
            return { content: "Commander target session is unavailable." }
          }
        })
      },
    }))
  },
})

function childSession(result: unknown): string | undefined {
  if (!object(result) || !object(result.metadata) || typeof result.metadata.sessionID !== "string") return
  if (result.metadata.status !== undefined && result.metadata.status !== "running" && result.metadata.status !== "completed") return
  return result.metadata.sessionID
}

function decisionIDFor(parent: string, message: string, call: string, child: string): string {
  return "subagent-" + hash([parent, message, call, child].join("\n"))
}

function referenced(result: Tool.Result, decision: string, parentMessage: string): Tool.Result {
  const reference = `Commander follow-up reference: ${decision}`
  const content = Array.isArray(result.content)
    ? [...result.content, { type: "text", text: reference }]
    : typeof result.content === "string"
      ? `${result.content}\n\n${reference}`
      : reference
  const metadata = object(result.metadata) ? result.metadata : {}
  return { ...result, content, metadata: { ...metadata, commanderDecisionID: decision, commanderParentMessageID: parentMessage } }
}

function nativeDecision(value: unknown, expected: string, parent: string): Readonly<{ parent: string; parentMessage: string; child: string }> | undefined {
  if (!Array.isArray(value)) return
  for (const message of value) {
    if (!object(message) || message.type !== "assistant" || !Array.isArray(message.content)) continue
    for (const part of message.content) {
      if (!object(part) || part.type !== "tool" || part.name !== "subagent" || !object(part.state) || part.state.status !== "completed" || !object(part.state.metadata)) continue
      const metadata = part.state.metadata
      if (metadata.commanderDecisionID !== expected || typeof metadata.commanderParentMessageID !== "string" || typeof metadata.sessionID !== "string") continue
      return { parent, parentMessage: metadata.commanderParentMessageID, child: metadata.sessionID }
    }
  }
}

function admission(value: unknown, session: string, id: string, text: string, metadata: Readonly<{ fromCommander: true; [key: string]: string }>) {
  return object(value) && value.sessionID === session && value.id === id && value.type === "user" && object(value.payload) && value.payload.text === text && object(value.payload.metadata) && Object.entries(metadata).every(([key, expected]) => value.payload.metadata[key] === expected)
}

function decode(value: unknown): Decision | undefined {
  if (!object(value) || typeof value.parent !== "string" || typeof value.parentMessage !== "string" || typeof value.child !== "string" || typeof value.project !== "string" || !object(value.requests)) return
  const requests: Record<string, string> = {}
  for (const [key, digest] of Object.entries(value.requests)) {
    if (!requestID(key) || typeof digest !== "string" || !/^[a-f0-9]{64}$/.test(digest)) return
    requests[key] = digest
  }
  return { parent: value.parent, parentMessage: value.parentMessage, child: value.child, project: value.project, requests }
}

function decisionID(value: string) { return /^(?:subagent|project-session)-[a-f0-9]{64}$/.test(value) }
function sessionID(value: string) { return /^ses_[A-Za-z0-9]+$/.test(value) }
function requestID(value: string) { return /^[a-z0-9][a-z0-9_-]{0,255}$/i.test(value) }
function hash(value: string) { return createHash("sha256").update(value, "utf8").digest("hex") }
function object(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value) }

function projectRequestID(parent: string, project: string, request: string): string {
  return hash([parent, project, request].join("\n"))
}

function projectMessageIDFor(project: string, request: string): string {
  return "msg_commander_project_" + hash([project, request].join("\n"))
}

function projectSessionDecisionIDFor(parent: string, message: string, call: string, child: string): string {
  return "project-session-" + hash([parent, message, call, child].join("\n"))
}

function projectSessionReferenceID(parent: string, child: string): string {
  return hash([parent, child].join("\n"))
}

function projectSessionResult(project: string, session: string, request: string, decision: string) {
  return { content: JSON.stringify({ project_id: project, session_id: session, message_id: projectMessageIDFor(project, request), request_id: request, decision_id: decision }) }
}

function commanderAgentText(text: string): string {
  return `Commander-directed work:\n\n${text}`
}

function latestAssistant(messages: unknown): unknown {
  if (!Array.isArray(messages)) return undefined
  return messages.findLast((message) => object(message) && message.type === "assistant")
}

function followUpTarget(decision: string | undefined, session: string | undefined): Readonly<{ kind: "decision" | "session"; value: string }> | undefined {
  if (decision !== undefined && session !== undefined) return
  if (decision !== undefined && decisionID(decision)) return { kind: "decision", value: decision }
  if (session !== undefined && sessionID(session)) return { kind: "session", value: session }
}

function historicalProjectSession(messages: unknown, parent: string, child: string): Readonly<{ parent: string; parentMessage: string; child: string; project: string; messageID: string; requestID: string; callID: string }> | undefined {
  if (!Array.isArray(messages)) return
  for (const message of messages) {
    if (!object(message) || message.type !== "assistant" || typeof message.id !== "string" || !Array.isArray(message.content)) continue
    for (const part of message.content) {
      if (!object(part) || part.type !== "tool" || part.name !== "commander_create_project_session" || !object(part.state) || !object(part.state.input)) continue
      const input = part.state.input
      if (typeof input.project_id !== "string" || typeof input.request_id !== "string" || !requestID(input.request_id) || typeof part.id !== "string") continue
      const output = toolOutput(part.state.content)
      if (!output || output.session_id !== child || output.project_id !== input.project_id || output.request_id !== input.request_id || typeof output.message_id !== "string") continue
      return { parent, parentMessage: message.id, child, project: input.project_id, messageID: output.message_id, requestID: input.request_id, callID: part.id }
    }
  }
}

function toolOutput(value: unknown): Readonly<{ project_id: string; session_id: string; message_id: string; request_id: string }> | undefined {
  if (!Array.isArray(value)) return
  for (const part of value) {
    if (!object(part) || part.type !== "text" || typeof part.text !== "string") continue
    try {
      const parsed = JSON.parse(part.text)
      if (object(parsed) && typeof parsed.project_id === "string" && typeof parsed.session_id === "string" && typeof parsed.message_id === "string" && typeof parsed.request_id === "string") return parsed
    } catch {
      continue
    }
  }
}

function createdMessage(messages: unknown, id: string, project: string, request: string): boolean {
  if (!Array.isArray(messages)) return false
  return messages.some((message) => object(message) && message.type === "user" && message.id === id && object(message.metadata) && message.metadata.fromCommander === true && message.metadata.commanderProjectID === project && message.metadata.commanderRequestID === request)
}

function decodeProjectRequest(value: unknown): ProjectRequest | undefined {
  if (!object(value) || typeof value.parent !== "string" || typeof value.project !== "string" || typeof value.requestDigest !== "string" || typeof value.decisionID !== "string") return
  if (!/^[a-f0-9]{64}$/.test(value.requestDigest) || !decisionID(value.decisionID)) return
  return { parent: value.parent, project: value.project, requestDigest: value.requestDigest, decisionID: value.decisionID }
}

async function exclusive<T>(locks: Map<string, Promise<void>>, key: string, operation: () => Promise<T>): Promise<T> {
  const previous = locks.get(key) ?? Promise.resolve()
  let release = () => {}
  const current = new Promise<void>((resolve) => { release = resolve })
  const queued = previous.then(() => current)
  locks.set(key, queued)
  await previous
  try {
    return await operation()
  } finally {
    release()
    if (locks.get(key) === queued) locks.delete(key)
  }
}
