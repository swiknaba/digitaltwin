import {
  emptyConversation,
  bridgeRequestId,
  decodeStreamEvent,
  maxCapabilityLifetimeMs,
  streamCursor,
  type ActionResult,
  type ApplyResult,
  type AuthorizeResult,
  type BridgeActorId,
  type BridgeRequest,
  type BridgeRequestId,
  type CapabilityAction,
  type CapabilityBinding,
  type CapabilityPresentation,
  type CapabilityRejection,
  type CapabilityVerifier,
  type CommanderConversation,
  type CommanderConversationId,
  type CommanderRuntime,
  type ConversationStatus,
  type ConversationStore,
  type RequestedAction,
  type StreamEvent,
} from "./contract.ts"
import { commandCapabilityBinding } from "./capability-binding.ts"

const retainedEvents = 512
const retainedRequests = 256
type OpenResult = Readonly<{ ok: true; actorId: BridgeActorId; conversation: CommanderConversation }> | Readonly<{ ok: false; reason: CapabilityRejection }>
type ReconnectResult = Readonly<{ ok: true; conversation: CommanderConversation; events: readonly StreamEvent[]; resyncRequired: boolean }> | Readonly<{ ok: false; reason: "invalid_request" | CapabilityRejection }>

/** Serializes one global Commander conversation and never stores a capability proof. */
export class CommanderBridgeController {
  private readonly input: Readonly<{ actorId: BridgeActorId; conversationId: CommanderConversationId; runtime: CommanderRuntime; store: ConversationStore; verifier: CapabilityVerifier; now: () => Date }>
  private tail: Promise<void> = Promise.resolve()

  constructor(input: Readonly<{ actorId: BridgeActorId; conversationId: CommanderConversationId; runtime: CommanderRuntime; store: ConversationStore; verifier: CapabilityVerifier; now: () => Date }>) { this.input = input }

  async open(presentation: CapabilityPresentation): Promise<OpenResult> { return this.serial(async () => { const authorization = await this.authorize("read", presentation); return authorization.ok ? { ok: true, actorId: authorization.actorId, conversation: await this.loadOrCreate() } : authorization }) }

  async reconnect(presentation: CapabilityPresentation, after: unknown): Promise<ReconnectResult> {
    return this.serial(async () => {
      if (typeof after !== "number" || !Number.isSafeInteger(after) || after < 0) return { ok: false, reason: "invalid_request" }
      const authorization = await this.authorize("read", presentation)
      if (!authorization.ok) return authorization
      const conversation = await this.loadOrCreate()
      const first = conversation.events[0]?.cursor ?? streamCursor(conversation.lastCursor + 1)
      const resyncRequired = after < first - 1 || after > conversation.lastCursor
      return { ok: true, conversation, events: resyncRequired ? conversation.events : conversation.events.filter((event) => event.cursor > after), resyncRequired }
    })
  }

  async prompt(presentation: CapabilityPresentation, requestId: unknown, text: unknown): Promise<ActionResult> { return this.dispatch("prompt", presentation, requestId, text) }
  async steer(presentation: CapabilityPresentation, requestId: unknown, text: unknown): Promise<ActionResult> { return this.dispatch("steer", presentation, requestId, text) }
  async cancel(presentation: CapabilityPresentation, requestId: unknown): Promise<ActionResult> { return this.dispatch("cancel", presentation, requestId) }

  async apply(input: unknown): Promise<ApplyResult> {
    return this.serial(async () => {
      const event = decodeStreamEvent(input)
      if (!event) return { ok: false, reason: "invalid_event" }
      if (event.conversationId !== this.input.conversationId) return { ok: false, reason: "cross_conversation" }
      const conversation = await this.loadOrCreate()
      const atCursor = conversation.events.find((stored) => stored.cursor === event.cursor)
      if (atCursor) return sameEvent(atCursor, event) ? { ok: true, state: "duplicate" } : { ok: false, reason: "cursor_conflict" }
      if (conversation.events.some((stored) => stored.deliveryId === event.deliveryId)) return { ok: false, reason: "delivery_conflict" }
      if (event.cursor !== streamCursor(conversation.lastCursor + 1)) return { ok: false, reason: "stream_gap" }
      if (conversation.status === "ready" || isTerminal(conversation.status)) return { ok: false, reason: "invalid_event" }
      const status = event.kind === "final" ? "ready" : (conversation.status === "cancel_requested" ? "cancel_requested" : "streaming")
      return (await this.persist({ ...conversation, status, lastCursor: event.cursor, events: [...conversation.events, event].slice(-retainedEvents) })) ? { ok: true, state: "applied" } : { ok: false, reason: "persistence_conflict" }
    })
  }

  private async dispatch(action: RequestedAction, presentation: CapabilityPresentation, rawRequestId: unknown, rawText?: unknown): Promise<ActionResult> {
    return this.serial(async () => {
      if (typeof rawRequestId !== "string") return { ok: false, reason: "invalid_request" }
      let requestId: BridgeRequestId
      try { requestId = bridgeRequestId(rawRequestId) } catch { return { ok: false, reason: "invalid_request" } }
      const text = action === "cancel" ? undefined : validText(rawText)
      if (action !== "cancel" && text === undefined) return { ok: false, reason: "invalid_request" }
      const binding = commandCapabilityBinding(action, rawRequestId, text)
      const authorization = await this.authorize(action, presentation, binding)
      if (!authorization.ok) return authorization
      const conversation = await this.loadOrCreate()
      const existing = conversation.requests.find((request) => request.id === requestId)
      if (existing) {
        if (existing.action !== action || existing.payloadDigest !== binding.payloadDigest) return { ok: false, reason: "request_conflict" }
        return existing.state === "uncertain" ? { ok: false, reason: "uncertain" } : { ok: true, state: "already_recorded" }
      }
      if (isTerminal(conversation.status)) return { ok: false, reason: "terminal" }
      const pending: BridgeRequest = { id: requestId, action, payloadDigest: binding.payloadDigest, state: "pending" }
      if (!(await this.persist({ ...conversation, status: action === "prompt" ? "streaming" : conversation.status, requests: retainRequests([...conversation.requests, pending]) }))) return { ok: false, reason: "persistence_conflict" }
      try {
        if (action === "prompt" && text !== undefined) await this.input.runtime.prompt({ conversationId: this.input.conversationId, requestId, text, actorId: authorization.actorId })
        if (action === "steer" && text !== undefined) await this.input.runtime.steer({ conversationId: this.input.conversationId, requestId, text, actorId: authorization.actorId })
        if (action === "cancel") {
          const result = await this.input.runtime.cancel({ conversationId: this.input.conversationId, requestId, actorId: authorization.actorId })
          await this.replaceRequest(requestId, "dispatched", result === "acknowledged" ? "cancel_requested" : undefined)
        } else await this.replaceRequest(requestId, "dispatched")
        return { ok: true, state: "dispatched" }
      } catch {
        await this.replaceRequest(requestId, "uncertain")
        return { ok: false, reason: "uncertain" }
      }
    })
  }

  private async replaceRequest(id: BridgeRequestId, state: BridgeRequest["state"], status?: ConversationStatus): Promise<void> {
    const conversation = await this.loadOrCreate()
    const requests = conversation.requests.map((request) => request.id === id ? { ...request, state } : request)
    if (!(await this.persist({ ...conversation, status: isTerminal(conversation.status) ? conversation.status : (status ?? conversation.status), requests }))) throw new Error("Durable request state conflict")
  }

  private async authorize(action: CapabilityAction, presentation: CapabilityPresentation, expectedBinding?: CapabilityBinding): Promise<AuthorizeResult> {
    const now = this.input.now()
    const decision = await this.input.verifier.consume({ action, expectedAudience: "commander-bridge", expectedConversationId: this.input.conversationId, ...(expectedBinding === undefined ? {} : { expectedBinding }), presentation, now })
    if (!decision.ok) return decision
    const capability = decision.capability
    if (capability.action !== action) return { ok: false, reason: "action_mismatch" }
    if (capability.audience !== "commander-bridge") return { ok: false, reason: "audience_mismatch" }
    if (capability.actorId !== this.input.actorId) return { ok: false, reason: "actor_mismatch" }
    if (capability.conversationId !== this.input.conversationId) return { ok: false, reason: "conversation_mismatch" }
    if (!sameBinding(capability.binding, expectedBinding)) return { ok: false, reason: "invalid" }
    const issued = capability.issuedAt.getTime(); const expires = capability.expiresAt.getTime()
    if (!Number.isFinite(issued) || !Number.isFinite(expires) || issued > now.getTime() || expires <= now.getTime() || expires - issued > maxCapabilityLifetimeMs) return { ok: false, reason: "expired" }
    return { ok: true, actorId: capability.actorId }
  }

  private async loadOrCreate(): Promise<CommanderConversation> {
    const current = await this.input.store.load(this.input.conversationId)
    if (current) return current
    const saved = await this.input.store.save({ conversation: emptyConversation(this.input.conversationId) })
    if (saved.ok) return saved.conversation
    const raced = await this.input.store.load(this.input.conversationId)
    if (!raced) throw new Error("Conversation creation conflict without a durable record")
    return raced
  }
  private async persist(conversation: CommanderConversation): Promise<boolean> { return (await this.input.store.save({ conversation, expectedVersion: conversation.version })).ok }
  private serial<T>(work: () => Promise<T>): Promise<T> { const result = this.tail.then(work, work); this.tail = result.then(() => undefined, () => undefined); return result }
}

function isTerminal(status: ConversationStatus): boolean { return status === "completed" || status === "canceled" || status === "failed" }
function sameBinding(left: CapabilityBinding | undefined, right: CapabilityBinding | undefined): boolean {
  return left === undefined && right === undefined || left !== undefined && right !== undefined && left.requestId === right.requestId && left.payloadDigest === right.payloadDigest
}
function isText(value: unknown): value is string { return typeof value === "string" && value.trim().length > 0 && value.length <= 16_000 }
function validText(value: unknown): string | undefined { return isText(value) ? value : undefined }
function retainRequests(requests: readonly BridgeRequest[]): readonly BridgeRequest[] {
  const unresolved = requests.filter((request) => request.state === "pending" || request.state === "uncertain")
  const dispatched = requests.filter((request) => request.state === "dispatched").slice(-Math.max(0, retainedRequests - unresolved.length))
  return [...unresolved, ...dispatched]
}
function sameEvent(left: StreamEvent, right: StreamEvent): boolean { return left.cursor === right.cursor && left.deliveryId === right.deliveryId && left.kind === right.kind && left.text === right.text && left.outcome === right.outcome }
