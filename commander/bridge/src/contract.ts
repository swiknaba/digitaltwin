export type CommanderConversationId = string & { readonly __brand: "CommanderConversationId" }
export type BridgeActorId = string & { readonly __brand: "BridgeActorId" }
export type BridgeRequestId = string & { readonly __brand: "BridgeRequestId" }
export type StreamCursor = number & { readonly __brand: "StreamCursor" }

export const capabilityActions = ["read", "prompt", "steer", "cancel", "result"] as const
export type CapabilityAction = (typeof capabilityActions)[number]
export type CapabilityPresentation = Readonly<{ token: string }>
export const maxCapabilityLifetimeMs = 5 * 60 * 1000

export type VerifiedCapability = Readonly<{
  action: CapabilityAction
  actorId: BridgeActorId
  audience: "commander-bridge"
  conversationId: CommanderConversationId
  issuedAt: Date
  expiresAt: Date
  nonce: string
}>

export type CapabilityRejection = "action_mismatch" | "actor_mismatch" | "audience_mismatch" | "conversation_mismatch" | "expired" | "invalid" | "replayed"
export type CapabilityDecision = Readonly<{ ok: true; capability: VerifiedCapability }> | Readonly<{ ok: false; reason: CapabilityRejection }>

/** The verifier atomically validates and consumes a proof nonce at the operator boundary. */
export interface CapabilityVerifier {
  consume(input: Readonly<{ action: CapabilityAction; expectedAudience: "commander-bridge"; expectedConversationId: CommanderConversationId; presentation: CapabilityPresentation; now: Date }>): Promise<CapabilityDecision>
}

type StreamEventBase = Readonly<{ conversationId: CommanderConversationId; cursor: StreamCursor; deliveryId: string; text: string }>
export type StreamEvent =
  | (StreamEventBase & Readonly<{ kind: "delta" | "notice"; outcome?: never }>)
  | (StreamEventBase & Readonly<{ kind: "final"; outcome: "completed" | "canceled" | "failed" }>)

export type ConversationStatus = "ready" | "streaming" | "cancel_requested" | "completed" | "canceled" | "failed"
export type RequestedAction = "prompt" | "steer" | "cancel"
export type RequestState = "pending" | "dispatched" | "uncertain"
export type BridgeRequest = Readonly<{ id: BridgeRequestId; action: RequestedAction; state: RequestState }>

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
export type ActionResult = Readonly<{ ok: true; state: "dispatched" | "already_recorded" }> | Readonly<{ ok: false; reason: CapabilityRejection | "invalid_request" | "persistence_conflict" | "terminal" | "uncertain" }>
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
export function streamCursor(value: number): StreamCursor {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("Invalid stream cursor")
  return value as StreamCursor
}
export function emptyConversation(id: CommanderConversationId): CommanderConversation {
  return { id, version: 0, status: "ready", lastCursor: streamCursor(0), events: [], requests: [] }
}
