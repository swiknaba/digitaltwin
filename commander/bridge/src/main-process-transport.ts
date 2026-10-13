import { commandCapabilityBinding } from "./capability-binding.ts"
import { decodeCommanderConversation, decodeStreamEvent } from "./contract.ts"
import type { ActionResult, CapabilityAction, CapabilityBinding, CapabilityPresentation, CommanderConversation, StreamEvent } from "./contract.ts"

export interface MainProcessCapabilityIssuer {
  /** The implementation derives the actor and durable conversation from operator-owned bootstrap state. */
  issue(input: Readonly<{ action: CapabilityAction; binding?: CapabilityBinding }>): Promise<CapabilityPresentation>
}

export interface MainProcessFetch {
  fetch(input: string, init: Readonly<{ method: "POST"; headers: Readonly<Record<string, string>>; body: string }>): Promise<Readonly<{ status: number; json(): Promise<unknown> }>>
}

/**
 * Desktop main-process client. It is the only UI-side code that sees an ephemeral
 * capability, and never returns that proof to the renderer.
 */
export class CommanderMainProcessTransport {
  private readonly input: Readonly<{ baseUrl: string; capabilityIssuer: MainProcessCapabilityIssuer; fetch: MainProcessFetch }>

  constructor(input: Readonly<{ baseUrl: string; capabilityIssuer: MainProcessCapabilityIssuer; fetch: MainProcessFetch }>) {
    const url = new URL(input.baseUrl)
    if (url.protocol !== "https:" && url.hostname !== "127.0.0.1" && url.hostname !== "::1" && url.hostname !== "localhost")
      throw new Error("Commander bridge URL must use HTTPS or loopback")
    if (url.username.length > 0 || url.password.length > 0 || url.pathname !== "/" || url.search.length > 0 || url.hash.length > 0)
      throw new Error("Commander bridge URL must be a credential-free origin")
    this.input = input
  }

  async prompt(requestId: string, text: string): Promise<ActionResult> {
    return this.command("prompt", "/v1/commander/prompt", { requestId, text })
  }

  async steer(requestId: string, text: string): Promise<ActionResult> {
    return this.command("steer", "/v1/commander/steer", { requestId, text })
  }

  async cancel(requestId: string): Promise<ActionResult> {
    return this.command("cancel", "/v1/commander/cancel", { requestId })
  }

  async open(): Promise<OpenTransportResult> { return this.read("/v1/commander/open", {}) }

  async reconnect(after: number): Promise<ReconnectTransportResult> { return this.read("/v1/commander/reconnect", { after }) }

  private async command(action: "prompt" | "steer" | "cancel", path: string, body: Readonly<Record<string, string>>): Promise<ActionResult> {
    try {
      const requestId = body.requestId
      const binding = typeof requestId === "string" ? commandCapabilityBinding(action, requestId, body.text) : undefined
      const capability = await this.input.capabilityIssuer.issue(binding === undefined ? { action } : { action, binding })
      const response = await this.input.fetch.fetch(new URL(path, this.input.baseUrl).toString(), {
        method: "POST",
        headers: { authorization: `Bearer ${capability.token}`, "content-type": "application/json" },
        body: JSON.stringify(body),
      })
      return decodeActionResult(response.status, await response.json())
    } catch {
      return { ok: false, reason: "uncertain" }
    }
  }

  private read(path: "/v1/commander/open", body: Readonly<Record<string, number>>): Promise<OpenTransportResult>
  private read(path: "/v1/commander/reconnect", body: Readonly<Record<string, number>>): Promise<ReconnectTransportResult>
  private async read(path: "/v1/commander/open" | "/v1/commander/reconnect", body: Readonly<Record<string, number>>): Promise<OpenTransportResult | ReconnectTransportResult> {
    try {
      const capability = await this.input.capabilityIssuer.issue({ action: "read" })
      const response = await this.input.fetch.fetch(new URL(path, this.input.baseUrl).toString(), { method: "POST", headers: { authorization: `Bearer ${capability.token}`, "content-type": "application/json" }, body: JSON.stringify(body) })
      const decoded = decodeReadResult(response.status, await response.json(), path === "/v1/commander/reconnect")
      return decoded
    } catch { return { ok: false, reason: "uncertain" } }
  }
}

export type OpenTransportResult = Readonly<{ ok: true; actorId: string; conversation: CommanderConversation }> | Readonly<{ ok: false; reason: "invalid" | "uncertain" }>
export type ReconnectTransportResult = Readonly<{ ok: true; conversation: CommanderConversation; events: readonly StreamEvent[]; resyncRequired: boolean }> | Readonly<{ ok: false; reason: "invalid" | "uncertain" }>

function decodeActionResult(status: number, value: unknown): ActionResult {
  if (!isRecord(value) || typeof value.ok !== "boolean") return { ok: false, reason: "uncertain" }
  if (value.ok === true && (value.state === "dispatched" || value.state === "already_recorded")) return { ok: true, state: value.state }
  if (value.ok === false && typeof value.reason === "string" && isFailure(value.reason)) return { ok: false, reason: value.reason }
  return status === 401 ? { ok: false, reason: "invalid" } : { ok: false, reason: "uncertain" }
}

function decodeReadResult(status: number, value: unknown, reconnect: boolean): OpenTransportResult | ReconnectTransportResult {
  if (!isRecord(value) || value.ok !== true) return { ok: false, reason: status === 401 ? "invalid" : "uncertain" }
  const conversation = decodeCommanderConversation(value.conversation)
  if (!conversation) return { ok: false, reason: "uncertain" }
  if (!reconnect && typeof value.actorId === "string") return { ok: true, actorId: value.actorId, conversation }
  if (reconnect && Array.isArray(value.events) && typeof value.resyncRequired === "boolean") {
    const events = value.events.map(decodeStreamEvent)
    return allDefined(events) ? { ok: true, conversation, events, resyncRequired: value.resyncRequired } : { ok: false, reason: "uncertain" }
  }
  return { ok: false, reason: "uncertain" }
}

function isFailure(value: string): value is Extract<ActionResult, { ok: false }>["reason"] {
  return value === "action_mismatch" || value === "actor_mismatch" || value === "audience_mismatch" || value === "conversation_mismatch" || value === "expired" || value === "invalid" || value === "replayed" || value === "invalid_request" || value === "request_conflict" || value === "persistence_conflict" || value === "terminal" || value === "uncertain"
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function allDefined<T>(values: readonly (T | undefined)[]): values is readonly T[] {
  return values.every((value): value is T => value !== undefined)
}
