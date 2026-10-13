import {
  emptyConversation, bridgeRequestId, decodeStreamEvent, maxCapabilityLifetimeMs, streamCursor, turnIdForRequest,
  type ActionResult, type ApplyResult, type AuthorizeResult, type BridgeActorId, type BridgeRequest, type BridgeRequestId,
  type CapabilityAction, type CapabilityBinding, type CapabilityPresentation, type CapabilityRejection, type CapabilityVerifier,
  type CommanderConversation, type CommanderConversationId, type CommanderRuntime, type CommanderTurnId, type ConversationStatus,
  type ConversationStore, type RequestedAction, type StreamEvent,
} from "./contract.ts"
import { commandCapabilityBinding } from "./capability-binding.ts"

const retainedEvents = 512
const retainedRequests = 256
type OpenResult = Readonly<{ ok: true; actorId: BridgeActorId; conversation: CommanderConversation }> | Readonly<{ ok: false; reason: CapabilityRejection }>
type ReconnectResult = Readonly<{ ok: true; conversation: CommanderConversation; events: readonly StreamEvent[]; resyncRequired: boolean }> | Readonly<{ ok: false; reason: "invalid_request" | CapabilityRejection }>
type PreparedDispatch = Readonly<{ ok: true; action: RequestedAction; requestId: BridgeRequestId; turnId: CommanderTurnId; text?: string; actorId: BridgeActorId }> | Readonly<{ ok: false; result: ActionResult }>

/** Persists a turn before runtime I/O; only durable mutations use the local queue. */
export class CommanderBridgeController {
  private readonly input: Readonly<{ actorId: BridgeActorId; conversationId: CommanderConversationId; runtime: CommanderRuntime; store: ConversationStore; verifier: CapabilityVerifier; now: () => Date }>
  private tail: Promise<void> = Promise.resolve()

  constructor(input: Readonly<{ actorId: BridgeActorId; conversationId: CommanderConversationId; runtime: CommanderRuntime; store: ConversationStore; verifier: CapabilityVerifier; now: () => Date }>) { this.input = input }

  async open(presentation: CapabilityPresentation): Promise<OpenResult> {
    return this.serial(async () => {
      const authorization = await this.authorize("read", presentation)
      return authorization.ok ? { ok: true, actorId: authorization.actorId, conversation: await this.loadOrCreate() } : authorization
    })
  }

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
      if (conversation.activeTurn?.id !== event.turnId) return { ok: false, reason: "stale_turn" }
      const next = event.kind === "final"
        ? { ...conversation, status: "ready" as const, activeTurn: undefined, lastCursor: event.cursor, events: retainEvents([...conversation.events, event]) }
        : { ...conversation, status: conversation.status === "cancel_requested" ? "cancel_requested" as const : "streaming" as const, lastCursor: event.cursor, events: retainEvents([...conversation.events, event]) }
      return (await this.persist(next)) ? { ok: true, state: "applied" } : { ok: false, reason: "persistence_conflict" }
    })
  }

  private async dispatch(action: RequestedAction, presentation: CapabilityPresentation, rawRequestId: unknown, rawText?: unknown): Promise<ActionResult> {
    const prepared = await this.serial(() => this.prepareDispatch(action, presentation, rawRequestId, rawText))
    if (!prepared.ok) return prepared.result
    // Runtime promises are intentionally awaited outside `serial`: a slow prompt may not block cancel or event delivery.
    try {
      if (prepared.action === "prompt" && prepared.text !== undefined) {
        const result = await this.input.runtime.prompt({ conversationId: this.input.conversationId, requestId: prepared.requestId, turnId: prepared.turnId, text: prepared.text, actorId: prepared.actorId })
        if (result.turnId !== prepared.turnId) return this.serial(() => this.markUncertain(prepared.requestId, prepared.turnId))
      } else if (prepared.action === "steer" && prepared.text !== undefined) {
        await this.input.runtime.steer({ conversationId: this.input.conversationId, requestId: prepared.requestId, turnId: prepared.turnId, text: prepared.text, actorId: prepared.actorId })
      } else if (prepared.action === "cancel") {
        const result = await this.input.runtime.cancel({ conversationId: this.input.conversationId, requestId: prepared.requestId, turnId: prepared.turnId, actorId: prepared.actorId })
        return this.serial(() => this.finishDispatch(prepared.requestId, prepared.turnId, result === "already_terminal"))
      }
      return this.serial(() => this.finishDispatch(prepared.requestId, prepared.turnId, false))
    } catch { return this.serial(() => this.markUncertain(prepared.requestId, prepared.turnId)) }
  }

  private async prepareDispatch(action: RequestedAction, presentation: CapabilityPresentation, rawRequestId: unknown, rawText?: unknown): Promise<PreparedDispatch> {
    if (typeof rawRequestId !== "string") return { ok: false, result: { ok: false, reason: "invalid_request" } }
    let requestId: BridgeRequestId
    try { requestId = bridgeRequestId(rawRequestId) } catch { return { ok: false, result: { ok: false, reason: "invalid_request" } } }
    const text = action === "cancel" ? undefined : validText(rawText)
    if (action !== "cancel" && text === undefined) return { ok: false, result: { ok: false, reason: "invalid_request" } }
    const binding = commandCapabilityBinding(action, rawRequestId, text)
    const authorization = await this.authorize(action, presentation, binding)
    if (!authorization.ok) return { ok: false, result: authorization }
    const conversation = await this.loadOrCreate()
    const existing = conversation.requests.find((request) => request.id === requestId)
    if (existing) {
      if (existing.action !== action || existing.payloadDigest !== binding.payloadDigest) return { ok: false, result: { ok: false, reason: "request_conflict" } }
      return { ok: false, result: existing.state === "uncertain" ? { ok: false, reason: "uncertain" } : { ok: true, state: "already_recorded" } }
    }
    const turnId = action === "prompt" ? turnIdForRequest(requestId) : conversation.activeTurn?.id
    if (!turnId || (action === "prompt" && conversation.status !== "ready")) return { ok: false, result: { ok: false, reason: "terminal" } }
    const pending: BridgeRequest = { id: requestId, action, turnId, payloadDigest: binding.payloadDigest, state: "pending" }
    const next = action === "prompt"
      ? { ...conversation, status: "starting" as const, activeTurn: { id: turnId, promptRequestId: requestId }, requests: retainRequests([...conversation.requests, pending]) }
      : { ...conversation, status: action === "cancel" ? "cancel_requested" as const : conversation.status, requests: retainRequests([...conversation.requests, pending]) }
    if (!(await this.persist(next))) return { ok: false, result: { ok: false, reason: "persistence_conflict" } }
    return { ok: true, action, requestId, turnId, ...(text === undefined ? {} : { text }), actorId: authorization.actorId }
  }

  private async finishDispatch(id: BridgeRequestId, turnId: CommanderTurnId, alreadyTerminal: boolean): Promise<ActionResult> {
    const conversation = await this.loadOrCreate()
    const request = conversation.requests.find((candidate) => candidate.id === id)
    if (!request || request.turnId !== turnId || request.state === "uncertain") return { ok: false, reason: "uncertain" }
    if (request.state === "dispatched") return { ok: true, state: "already_recorded" }
    const terminal = alreadyTerminal && conversation.activeTurn?.id === turnId
    const next = { ...conversation, status: terminal ? "ready" as const : conversation.status, ...(terminal ? { activeTurn: undefined } : {}), requests: replaceRequest(conversation.requests, id, "dispatched") }
    return (await this.persist(next)) ? { ok: true, state: "dispatched" } : { ok: false, reason: "uncertain" }
  }

  private async markUncertain(id: BridgeRequestId, turnId: CommanderTurnId): Promise<ActionResult> {
    const conversation = await this.loadOrCreate()
    const request = conversation.requests.find((candidate) => candidate.id === id)
    if (!request || request.turnId !== turnId || request.state === "uncertain") return { ok: false, reason: "uncertain" }
    if (!(await this.persist({ ...conversation, requests: replaceRequest(conversation.requests, id, "uncertain") }))) return { ok: false, reason: "uncertain" }
    return { ok: false, reason: "uncertain" }
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

function sameBinding(left: CapabilityBinding | undefined, right: CapabilityBinding | undefined): boolean { return left === undefined && right === undefined || left !== undefined && right !== undefined && left.requestId === right.requestId && left.payloadDigest === right.payloadDigest }
function validText(value: unknown): string | undefined { return typeof value === "string" && value.trim().length > 0 && value.length <= 16_000 ? value : undefined }
function retainEvents(events: readonly StreamEvent[]): readonly StreamEvent[] { return events.slice(-retainedEvents) }
function retainRequests(requests: readonly BridgeRequest[]): readonly BridgeRequest[] { const unresolved = requests.filter((request) => request.state === "pending" || request.state === "uncertain"); const dispatched = requests.filter((request) => request.state === "dispatched").slice(-Math.max(0, retainedRequests - unresolved.length)); return [...unresolved, ...dispatched] }
function replaceRequest(requests: readonly BridgeRequest[], id: BridgeRequestId, state: BridgeRequest["state"]): readonly BridgeRequest[] { return requests.map((request) => request.id === id ? { ...request, state } : request) }
function sameEvent(left: StreamEvent, right: StreamEvent): boolean { return left.cursor === right.cursor && left.deliveryId === right.deliveryId && left.turnId === right.turnId && left.kind === right.kind && left.text === right.text && left.outcome === right.outcome }
