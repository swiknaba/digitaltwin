export type CommanderConversationId = string & { readonly __brand: "CommanderConversationId" }
export type BridgeActorId = string & { readonly __brand: "BridgeActorId" }
export type BridgeRequestId = string & { readonly __brand: "BridgeRequestId" }
export type CommanderTurnId = string & { readonly __brand: "CommanderTurnId" }
export type CapabilityPayloadDigest = string & { readonly __brand: "CapabilityPayloadDigest" }
export type StreamCursor = number & { readonly __brand: "StreamCursor" }

export const capabilityActions = ["read", "prompt", "steer", "cancel", "result"] as const
export type CapabilityAction = (typeof capabilityActions)[number]
export type CapabilityPresentation = Readonly<{ token: string }>
export type CapabilityBinding = Readonly<{ requestId: BridgeRequestId; payloadDigest: CapabilityPayloadDigest }>
export const maxCapabilityLifetimeMs = 5 * 60 * 1000

export type VerifiedCapability = Readonly<{
  action: CapabilityAction
  actorId: BridgeActorId
  audience: "commander-bridge"
  conversationId: CommanderConversationId
  issuedAt: Date
  expiresAt: Date
  nonce: string
  binding?: CapabilityBinding
}>

export type CapabilityRejection = "action_mismatch" | "actor_mismatch" | "audience_mismatch" | "conversation_mismatch" | "expired" | "invalid" | "replayed"
export type CapabilityDecision = Readonly<{ ok: true; capability: VerifiedCapability }> | Readonly<{ ok: false; reason: CapabilityRejection }>

/** The verifier atomically validates and consumes a proof nonce at the operator boundary. */
export interface CapabilityVerifier {
  consume(input: Readonly<{ action: CapabilityAction; expectedAudience: "commander-bridge"; expectedConversationId: CommanderConversationId; expectedBinding?: CapabilityBinding; presentation: CapabilityPresentation; now: Date }>): Promise<CapabilityDecision>
}

/**
 * An optional, non-authorizing reference to an OpenCode message. The runtime and
 * project namespaces prevent identical local session ids from being conflated.
 */
export type OpenCodeMessageProvenance = Readonly<{
  runtimeId: string
  projectId: string
  sessionId: string
  messageId: string
  agentId?: string
  parentSessionId?: string
}>

type StreamEventBase = Readonly<{ conversationId: CommanderConversationId; cursor: StreamCursor; deliveryId: string; text: string; provenance?: OpenCodeMessageProvenance }>
export type StreamEvent =
  | (StreamEventBase & Readonly<{ turnId: CommanderTurnId; kind: "delta" | "notice"; outcome?: never }>)
  | (StreamEventBase & Readonly<{ turnId: CommanderTurnId; kind: "final"; outcome: "completed" | "canceled" | "failed" }>)

/** Only these states are durable. A final runtime outcome returns the conversation to ready. */
export type ConversationStatus = "ready" | "starting" | "streaming" | "cancel_requested"
export type RequestedAction = "prompt" | "steer" | "cancel"
export type RequestState = "pending" | "dispatched" | "uncertain"
export type ActiveTurn = Readonly<{ id: CommanderTurnId; promptRequestId: BridgeRequestId }>
export type BridgeRequest = Readonly<{ id: BridgeRequestId; action: RequestedAction; payloadDigest: CapabilityPayloadDigest; state: RequestState; turnId: CommanderTurnId }>

export type CommanderConversation = Readonly<{
  id: CommanderConversationId
  version: number
  status: ConversationStatus
  activeTurn?: ActiveTurn
  lastCursor: StreamCursor
  events: readonly StreamEvent[]
  requests: readonly BridgeRequest[]
}>

export type SaveResult = Readonly<{ ok: true; conversation: CommanderConversation }> | Readonly<{ ok: false; reason: "version_conflict" }>
/** Durable storage never contains a capability presentation or runtime credential. */
export interface ConversationStore {
  load(id: CommanderConversationId): Promise<CommanderConversation | undefined>
  save(input: Readonly<{ conversation: CommanderConversation; expectedVersion?: number }>): Promise<SaveResult>
}

export interface CommanderRuntime {
  prompt(input: Readonly<{ conversationId: CommanderConversationId; requestId: BridgeRequestId; turnId: CommanderTurnId; text: string; actorId: BridgeActorId }>): Promise<Readonly<{ state: "accepted"; turnId: CommanderTurnId }>>
  steer(input: Readonly<{ conversationId: CommanderConversationId; requestId: BridgeRequestId; turnId: CommanderTurnId; text: string; actorId: BridgeActorId }>): Promise<void>
  cancel(input: Readonly<{ conversationId: CommanderConversationId; requestId: BridgeRequestId; turnId: CommanderTurnId; actorId: BridgeActorId }>): Promise<"acknowledged" | "already_terminal">
}

export type AuthorizeResult = Readonly<{ ok: true; actorId: BridgeActorId }> | Readonly<{ ok: false; reason: CapabilityRejection }>
export type ActionResult = Readonly<{ ok: true; state: "dispatched" | "already_recorded" }> | Readonly<{ ok: false; reason: CapabilityRejection | "invalid_request" | "request_conflict" | "persistence_conflict" | "terminal" | "uncertain" }>
export type ApplyResult = Readonly<{ ok: true; state: "applied" | "duplicate" }> | Readonly<{ ok: false; reason: "cross_conversation" | "cursor_conflict" | "delivery_conflict" | "invalid_event" | "stale_turn" | "stream_gap" | "persistence_conflict" }>

export function commanderConversationId(value: string): CommanderConversationId {
  if (!/^commander:[a-z0-9][a-z0-9_-]{0,127}$/i.test(value)) throw new Error("Invalid Commander conversation id")
  return value as CommanderConversationId
}
export function bridgeActorId(value: string): BridgeActorId {
  if (!/^[a-z0-9][a-z0-9_.@-]{0,127}$/i.test(value)) throw new Error("Invalid bridge actor id")
  return value as BridgeActorId
}
export function bridgeRequestId(value: string): BridgeRequestId {
  if (!/^[a-z0-9][a-z0-9_-]{0,127}$/i.test(value)) throw new Error("Invalid bridge request id")
  return value as BridgeRequestId
}
export function commanderTurnId(value: string): CommanderTurnId {
  if (!/^turn:[a-z0-9][a-z0-9_-]{0,127}$/i.test(value)) throw new Error("Invalid Commander turn id")
  return value as CommanderTurnId
}
/**
 * The bridge chooses a turn before invoking the runtime, so an early runtime event
 * is still bound to persisted state and a late event cannot attach to the next turn.
 */
export function turnIdForRequest(requestId: BridgeRequestId): CommanderTurnId {
  return commanderTurnId(`turn:${requestId}`)
}
export function capabilityPayloadDigest(value: string): CapabilityPayloadDigest {
  if (!/^[a-f0-9]{64}$/.test(value)) throw new Error("Invalid capability payload digest")
  return value as CapabilityPayloadDigest
}
export function streamCursor(value: number): StreamCursor {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("Invalid stream cursor")
  return value as StreamCursor
}
export function emptyConversation(id: CommanderConversationId): CommanderConversation {
  return { id, version: 0, status: "ready", lastCursor: streamCursor(0), events: [], requests: [] }
}

export function decodeStreamEvent(value: unknown): StreamEvent | undefined {
  if (!isRecord(value) || typeof value.conversationId !== "string" || typeof value.turnId !== "string" || typeof value.cursor !== "number" || typeof value.deliveryId !== "string" || typeof value.text !== "string") return undefined
  if (!Number.isSafeInteger(value.cursor) || value.cursor < 1 || value.deliveryId.length === 0 || value.deliveryId.length > 256 || value.text.length > 64_000) return undefined
  try {
    const provenance = value.provenance === undefined ? undefined : decodeOpenCodeMessageProvenance(value.provenance)
    if (value.provenance !== undefined && provenance === undefined) return undefined
    const base = { conversationId: commanderConversationId(value.conversationId), turnId: commanderTurnId(value.turnId), cursor: streamCursor(value.cursor), deliveryId: value.deliveryId, text: value.text, ...(provenance === undefined ? {} : { provenance }) }
    if (value.kind === "delta" || value.kind === "notice") return { ...base, kind: value.kind }
    if (value.kind === "final" && (value.outcome === "completed" || value.outcome === "canceled" || value.outcome === "failed")) return { ...base, kind: "final", outcome: value.outcome }
  } catch {}
  return undefined
}

export function decodeOpenCodeMessageProvenance(value: unknown): OpenCodeMessageProvenance | undefined {
  if (!isRecord(value) || typeof value.runtimeId !== "string" || typeof value.projectId !== "string" || typeof value.sessionId !== "string" || typeof value.messageId !== "string") return undefined
  if (!nonEmptyIdentifier(value.runtimeId) || !nonEmptyIdentifier(value.projectId) || !/^ses_[a-zA-Z0-9_-]+$/.test(value.sessionId) || !/^msg_[a-zA-Z0-9_-]+$/.test(value.messageId)) return undefined
  if (value.agentId !== undefined && (typeof value.agentId !== "string" || !nonEmptyIdentifier(value.agentId))) return undefined
  if (value.parentSessionId !== undefined && (typeof value.parentSessionId !== "string" || !/^ses_[a-zA-Z0-9_-]+$/.test(value.parentSessionId))) return undefined
  return { runtimeId: value.runtimeId, projectId: value.projectId, sessionId: value.sessionId, messageId: value.messageId, ...(value.agentId === undefined ? {} : { agentId: value.agentId }), ...(value.parentSessionId === undefined ? {} : { parentSessionId: value.parentSessionId }) }
}

export function decodeCommanderConversation(value: unknown): CommanderConversation | undefined {
  if (!isRecord(value) || typeof value.id !== "string" || typeof value.version !== "number" || !isStatus(value.status) || typeof value.lastCursor !== "number" || !Array.isArray(value.events) || !Array.isArray(value.requests)) return undefined
  if (!Number.isSafeInteger(value.version) || value.version < 0) return undefined
  try {
    const events = value.events.map(decodeStreamEvent)
    if (!allDefined(events)) return undefined
    const requests = value.requests.map(decodeRequest)
    if (!allDefined(requests)) return undefined
    const activeTurn = value.activeTurn === undefined ? undefined : decodeActiveTurn(value.activeTurn)
    if (value.activeTurn !== undefined && activeTurn === undefined) return undefined
    const conversation = { id: commanderConversationId(value.id), version: value.version, status: value.status, ...(activeTurn === undefined ? {} : { activeTurn }), lastCursor: streamCursor(value.lastCursor), events, requests }
    return isValidConversationState(conversation) ? conversation : undefined
  } catch { return undefined }
}

function decodeRequest(value: unknown): BridgeRequest | undefined {
  if (!isRecord(value) || typeof value.id !== "string" || typeof value.turnId !== "string" || typeof value.payloadDigest !== "string" || !isRequestedAction(value.action) || !isRequestState(value.state)) return undefined
  try { return { id: bridgeRequestId(value.id), turnId: commanderTurnId(value.turnId), action: value.action, payloadDigest: capabilityPayloadDigest(value.payloadDigest), state: value.state } } catch { return undefined }
}
function decodeActiveTurn(value: unknown): ActiveTurn | undefined {
  if (!isRecord(value) || typeof value.id !== "string" || typeof value.promptRequestId !== "string") return undefined
  try { return { id: commanderTurnId(value.id), promptRequestId: bridgeRequestId(value.promptRequestId) } } catch { return undefined }
}
export function isValidConversationState(value: CommanderConversation): boolean {
  if (!value.events.every((event, index) => event.conversationId === value.id && (index === 0 || event.cursor > value.events[index - 1]!.cursor))) return false
  if (value.events.length === 0 && value.lastCursor !== streamCursor(0)) return false
  if (value.events.length > 0 && value.events[value.events.length - 1]!.cursor !== value.lastCursor) return false
  if (new Set(value.requests.map((request) => request.id)).size !== value.requests.length) return false
  if (value.status === "ready") return value.activeTurn === undefined
  if (value.activeTurn === undefined) return false
  const prompt = value.requests.find((request) => request.id === value.activeTurn?.promptRequestId)
  return prompt?.action === "prompt" && prompt.turnId === value.activeTurn.id
}
function isStatus(value: unknown): value is ConversationStatus { return value === "ready" || value === "starting" || value === "streaming" || value === "cancel_requested" }
function isRequestedAction(value: unknown): value is RequestedAction { return value === "prompt" || value === "steer" || value === "cancel" }
function isRequestState(value: unknown): value is RequestState { return value === "pending" || value === "dispatched" || value === "uncertain" }
function isRecord(value: unknown): value is Readonly<Record<string, unknown>> { return typeof value === "object" && value !== null && !Array.isArray(value) }
function nonEmptyIdentifier(value: string): boolean { return value.length > 0 && value.length <= 256 }
function allDefined<T>(values: readonly (T | undefined)[]): values is readonly T[] { return values.every((value): value is T => value !== undefined) }
