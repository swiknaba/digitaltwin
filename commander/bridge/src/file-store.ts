import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { randomUUID } from "node:crypto"
import { dirname } from "node:path"
import {
  commanderConversationId,
  bridgeRequestId,
  streamCursor,
  type BridgeRequest,
  type CommanderConversation,
  type CommanderConversationId,
  type ConversationStatus,
  type ConversationStore,
  type SaveResult,
  type StreamEvent,
} from "./contract.ts"

type DiskState = Readonly<{ schema: 1; conversations: Readonly<Record<string, CommanderConversation>> }>

/**
 * Single-process durable store for the operator-run bridge. The file holds only
 * conversation/replay metadata and writes through a same-directory temporary file.
 * A horizontally scaled bridge must replace this adapter with a transactional store.
 */
export class FileConversationStore implements ConversationStore {
  private readonly path: string
  private tail: Promise<void> = Promise.resolve()

  constructor(path: string) {
    this.path = path
  }

  async load(id: CommanderConversationId): Promise<CommanderConversation | undefined> {
    return (await this.read()).conversations[id]
  }

  async save(input: Readonly<{ conversation: CommanderConversation; expectedVersion?: number }>): Promise<SaveResult> {
    const result = this.tail.then(() => this.saveNow(input), () => this.saveNow(input))
    this.tail = result.then(() => undefined, () => undefined)
    return result
  }

  private async saveNow(input: Readonly<{ conversation: CommanderConversation; expectedVersion?: number }>): Promise<SaveResult> {
    const state = await this.read()
    const current = state.conversations[input.conversation.id]
    if (input.expectedVersion !== undefined && current?.version !== input.expectedVersion)
      return { ok: false, reason: "version_conflict" }
    if (input.expectedVersion === undefined && current !== undefined) return { ok: false, reason: "version_conflict" }

    const conversation = { ...input.conversation, version: input.conversation.version + 1 }
    const next: DiskState = { schema: 1, conversations: { ...state.conversations, [conversation.id]: conversation } }
    await mkdir(dirname(this.path), { recursive: true, mode: 0o700 })
    const temporary = `${this.path}.${process.pid}.${randomUUID()}.tmp`
    await writeFile(temporary, JSON.stringify(next), { encoding: "utf8", mode: 0o600, flag: "wx" })
    await rename(temporary, this.path)
    return { ok: true, conversation }
  }

  private async read(): Promise<DiskState> {
    try {
      const parsed: unknown = JSON.parse(await readFile(this.path, "utf8"))
      return validate(parsed)
    } catch (error: unknown) {
      if (isMissingFile(error)) return { schema: 1, conversations: {} }
      throw error
    }
  }
}

function validate(value: unknown): DiskState {
  if (!isRecord(value) || value.schema !== 1 || !isRecord(value.conversations)) throw new Error("Invalid Commander conversation store")
  const conversations: Record<string, CommanderConversation> = {}
  for (const [id, raw] of Object.entries(value.conversations)) {
    const conversation = decodeConversation(raw)
    if (conversation.id !== id) throw new Error("Commander conversation key does not match its record")
    conversations[id] = conversation
  }
  return { schema: 1, conversations }
}

function decodeConversation(value: unknown): CommanderConversation {
  if (!isRecord(value) || typeof value.id !== "string" || !Number.isSafeInteger(value.version) || value.version < 0)
    throw new Error("Invalid Commander conversation record")
  if (!isStatus(value.status) || !Number.isSafeInteger(value.lastCursor) || value.lastCursor < 0)
    throw new Error("Invalid Commander conversation record")
  if (!Array.isArray(value.events) || !Array.isArray(value.requests))
    throw new Error("Invalid Commander conversation record")
  return {
    id: commanderConversationId(value.id),
    version: value.version,
    status: value.status,
    lastCursor: streamCursor(value.lastCursor),
    events: value.events.map(decodeEvent),
    requests: value.requests.map(decodeRequest),
  }
}

function isStatus(value: unknown): value is ConversationStatus {
  return value === "ready" || value === "streaming" || value === "cancel_requested" || value === "completed" || value === "canceled" || value === "failed"
}

function decodeEvent(value: unknown): StreamEvent {
  if (!isRecord(value) || typeof value.conversationId !== "string" || typeof value.cursor !== "number" || typeof value.deliveryId !== "string" || typeof value.text !== "string") throw new Error("Invalid Commander stream event")
  const base = { conversationId: commanderConversationId(value.conversationId), cursor: streamCursor(value.cursor), deliveryId: value.deliveryId, text: value.text }
  if (value.kind === "delta" || value.kind === "notice") return { ...base, kind: value.kind }
  if (value.kind === "final" && (value.outcome === "completed" || value.outcome === "canceled" || value.outcome === "failed")) return { ...base, kind: "final", outcome: value.outcome }
  throw new Error("Invalid Commander stream event")
}

function decodeRequest(value: unknown): BridgeRequest {
  if (!isRecord(value) || typeof value.id !== "string" || (value.action !== "prompt" && value.action !== "steer" && value.action !== "cancel") || (value.state !== "pending" && value.state !== "dispatched" && value.state !== "uncertain")) throw new Error("Invalid Commander request")
  return { id: bridgeRequestId(value.id), action: value.action, state: value.state }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function isMissingFile(error: unknown): error is NodeJS.ErrnoException {
  return isRecord(error) && error.code === "ENOENT"
}
