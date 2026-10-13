import type { CommanderConversation, CommanderConversationId, ConversationStore, SaveResult } from "./contract.ts"

/** Deterministic test store; production wiring must provide an operator-owned durable store. */
export class InMemoryConversationStore implements ConversationStore {
  readonly records = new Map<CommanderConversationId, CommanderConversation>()

  async load(id: CommanderConversationId): Promise<CommanderConversation | undefined> {
    return this.records.get(id)
  }

  async save(input: Readonly<{ conversation: CommanderConversation; expectedVersion?: number }>): Promise<SaveResult> {
    const current = this.records.get(input.conversation.id)

    if (input.expectedVersion !== undefined && current?.version !== input.expectedVersion)
      return { ok: false, reason: "version_conflict" }

    if (input.expectedVersion === undefined && current !== undefined) return { ok: false, reason: "version_conflict" }

    const conversation = { ...input.conversation, version: input.conversation.version + 1 }
    this.records.set(conversation.id, conversation)
    return { ok: true, conversation }
  }
}
