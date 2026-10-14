/**
 * Exact OpenCode location selected by the trusted main process. This is an
 * identifier, not an authorization capability; OpenCode's normal session API
 * still authorizes every request.
 */
export type OpenCodeMessageProvenance = Readonly<{
  runtimeId: string
  projectId: string
  sessionId: string
  messageId: string
  agentId?: string
  parentSessionId?: string
}>

export function decodeOpenCodeMessageProvenance(value: unknown): OpenCodeMessageProvenance | undefined {
  if (!isRecord(value) || typeof value.runtimeId !== "string" || typeof value.projectId !== "string" || typeof value.sessionId !== "string" || typeof value.messageId !== "string") return undefined
  if (!identifier(value.runtimeId) || !identifier(value.projectId) || !sessionId(value.sessionId) || !messageId(value.messageId)) return undefined
  if (value.agentId !== undefined && (typeof value.agentId !== "string" || !identifier(value.agentId))) return undefined
  if (value.parentSessionId !== undefined && (typeof value.parentSessionId !== "string" || !sessionId(value.parentSessionId))) return undefined
  return {
    runtimeId: value.runtimeId,
    projectId: value.projectId,
    sessionId: value.sessionId,
    messageId: value.messageId,
    ...(value.agentId === undefined ? {} : { agentId: value.agentId }),
    ...(value.parentSessionId === undefined ? {} : { parentSessionId: value.parentSessionId }),
  }
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function identifier(value: string): boolean {
  return value.length > 0 && value.length <= 256
}

function sessionId(value: string): boolean {
  return /^ses_[a-zA-Z0-9_-]+$/.test(value)
}

function messageId(value: string): boolean {
  return /^msg_[a-zA-Z0-9_-]+$/.test(value)
}
