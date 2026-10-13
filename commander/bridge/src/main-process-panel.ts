import { randomUUID } from "node:crypto"
import type { CommanderConversation, StreamEvent } from "./contract.ts"
import type { CommanderMainProcessTransport } from "./main-process-transport.ts"

export type CommanderPanelState =
  | Readonly<{ status: "not-configured"; events: readonly StreamEvent[] }>
  | Readonly<{ status: "active"; conversation: CommanderConversation; events: readonly StreamEvent[] }>
  | Readonly<{ status: "unavailable"; events: readonly StreamEvent[] }>

/**
 * The only renderer-facing main-process adapter. It generates request IDs and calls
 * the already operator-bootstrapped transport; a panel never sees a proof, identity,
 * bridge origin, or runtime credential.
 */
export class CommanderMainProcessPanel {
  private state: CommanderPanelState = { status: "not-configured", events: [] }
  private readonly transport: CommanderMainProcessTransport | undefined

  constructor(transport: CommanderMainProcessTransport | undefined) { this.transport = transport }

  snapshot(): CommanderPanelState { return this.state }

  async open(): Promise<CommanderPanelState> {
    if (!this.transport) return this.state
    const result = await this.transport.open()
    if (!result.ok) return this.setUnavailable()
    this.state = { status: "active", conversation: result.conversation, events: result.conversation.events }
    return this.reconnect(result.conversation.lastCursor)
  }

  async prompt(text: string): Promise<CommanderPanelState> {
    if (this.state.status !== "active" || !validText(text) || !this.transport) return this.setUnavailable()
    const result = await this.transport.prompt(randomUUID(), text)
    return result.ok ? this.state : this.setUnavailable()
  }

  async steer(text: string): Promise<CommanderPanelState> {
    if (this.state.status !== "active" || !validText(text) || !this.transport) return this.setUnavailable()
    const result = await this.transport.steer(randomUUID(), text)
    return result.ok ? this.state : this.setUnavailable()
  }

  async cancel(): Promise<CommanderPanelState> {
    if (this.state.status !== "active" || !this.transport) return this.setUnavailable()
    const result = await this.transport.cancel(randomUUID())
    return result.ok ? this.state : this.setUnavailable()
  }

  async reconnect(after: number): Promise<CommanderPanelState> {
    if (this.state.status !== "active" || !this.transport) return this.state
    const result = await this.transport.reconnect(after)
    if (!result.ok) return this.setUnavailable()
    const events = result.resyncRequired ? result.events : merge(this.state.events, result.events)
    this.state = { status: "active", conversation: result.conversation, events }
    return this.state
  }

  private setUnavailable(): CommanderPanelState { this.state = { status: "unavailable", events: this.state.events }; return this.state }
}

function validText(value: string): boolean { return value.trim().length > 0 && value.length <= 16_000 }
function merge(current: readonly StreamEvent[], incoming: readonly StreamEvent[]): readonly StreamEvent[] {
  const seen = new Set(current.map((event) => event.deliveryId))
  return [...current, ...incoming.filter((event) => !seen.has(event.deliveryId))]
}
