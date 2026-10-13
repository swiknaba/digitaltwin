export type CommanderConversationId = string & { readonly __brand: "CommanderConversationId" }
export type BridgeActorId = string & { readonly __brand: "BridgeActorId" }
export type BridgeRequestId = string & { readonly __brand: "BridgeRequestId" }
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

type StreamEventBase = Readonly<{ conversationId: CommanderConversationId; cursor: StreamCursor; deliveryId: string; text: string }>
export type StreamEvent =
  | (StreamEventBase & Readonly<{ kind: "delta" | "notice"; outcome?: never }>)
  | (StreamEventBase & Readonly<{ kind: "final"; outcome: "completed" | "canceled" | "failed" }>)

export type ConversationStatus = "ready" | "streaming" | "cancel_requested" | "completed" | "canceled" | "failed"
export type RequestedAction = "prompt" | "steer" | "cancel"
export type RequestState = "pending" | "dispatched" | "uncertain"
export type BridgeRequest = Readonly<{ id: BridgeRequestId; action: RequestedAction; payloadDigest: CapabilityPayloadDigest; state: RequestState }>

export type CommanderConversation = Readonly<{
  id: CommanderConversationId
  version: number
  status: ConversationStatus
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
  prompt(input: Readonly<{ conversationId: CommanderConversationId; requestId: BridgeRequestId; text: string; actorId: BridgeActorId }>): Promise<void>
  steer(input: Readonly<{ conversationId: CommanderConversationId; requestId: BridgeRequestId; text: string; actorId: BridgeActorId }>): Promise<void>
  cancel(input: Readonly<{ conversationId: CommanderConversationId; requestId: BridgeRequestId; actorId: BridgeActorId }>): Promise<"acknowledged" | "already_terminal">
}

export type AuthorizeResult = Readonly<{ ok: true; actorId: BridgeActorId }> | Readonly<{ ok: false; reason: CapabilityRejection }>
export type ActionResult = Readonly<{ ok: true; state: "dispatched" | "already_recorded" }> | Readonly<{ ok: false; reason: CapabilityRejection | "invalid_request" | "request_conflict" | "persistence_conflict" | "terminal" | "uncertain" }>
export type ApplyResult = Readonly<{ ok: true; state: "applied" | "duplicate" }> | Readonly<{ ok: false; reason: "cross_conversation" | "cursor_conflict" | "delivery_conflict" | "invalid_event" | "stream_gap" | "persistence_conflict" }>

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
  if (!isRecord(value) || typeof value.conversationId !== "string" || typeof value.cursor !== "number" || typeof value.deliveryId !== "string" || typeof value.text !== "string") return undefined
  if (!Number.isSafeInteger(value.cursor) || value.cursor < 1 || value.deliveryId.length === 0 || value.deliveryId.length > 256 || value.text.length > 64_000) return undefined
  try {
    const base = { conversationId: commanderConversationId(value.conversationId), cursor: streamCursor(value.cursor), deliveryId: value.deliveryId, text: value.text }
    if (value.kind === "delta" || value.kind === "notice") return { ...base, kind: value.kind }
    if (value.kind === "final" && (value.outcome === "completed" || value.outcome === "canceled" || value.outcome === "failed")) return { ...base, kind: "final", outcome: value.outcome }
  } catch {}
  return undefined
}

export function decodeCommanderConversation(value: unknown): CommanderConversation | undefined {
  if (!isRecord(value) || typeof value.id !== "string" || typeof value.version !== "number" || !isStatus(value.status) || typeof value.lastCursor !== "number" || !Array.isArray(value.events) || !Array.isArray(value.requests)) return undefined
  if (!Number.isSafeInteger(value.version) || value.version < 0) return undefined
  try {
    const events = value.events.map(decodeStreamEvent)
    if (!allDefined(events)) return undefined
    const requests = value.requests.map(decodeRequest)
    if (!allDefined(requests)) return undefined
    return { id: commanderConversationId(value.id), version: value.version, status: value.status, lastCursor: streamCursor(value.lastCursor), events, requests }
  } catch { return undefined }
}

function decodeRequest(value: unknown): BridgeRequest | undefined {
  if (!isRecord(value) || typeof value.id !== "string" || typeof value.payloadDigest !== "string" || !isRequestedAction(value.action) || !isRequestState(value.state)) return undefined
  try { return { id: bridgeRequestId(value.id), action: value.action, payloadDigest: capabilityPayloadDigest(value.payloadDigest), state: value.state } } catch { return undefined }
}
function isStatus(value: unknown): value is ConversationStatus { return value === "ready" || value === "streaming" || value === "cancel_requested" || value === "completed" || value === "canceled" || value === "failed" }
function isRequestedAction(value: unknown): value is RequestedAction { return value === "prompt" || value === "steer" || value === "cancel" }
function isRequestState(value: unknown): value is RequestState { return value === "pending" || value === "dispatched" || value === "uncertain" }
function isRecord(value: unknown): value is Readonly<Record<string, unknown>> { return typeof value === "object" && value !== null && !Array.isArray(value) }
function allDefined<T>(values: readonly (T | undefined)[]): values is readonly T[] { return values.every((value): value is T => value !== undefined) }
