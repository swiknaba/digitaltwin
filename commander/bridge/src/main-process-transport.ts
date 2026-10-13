import type { ActionResult, CapabilityAction, CapabilityPresentation } from "./contract.ts"

export interface MainProcessCapabilityIssuer {
  issue(action: CapabilityAction): Promise<CapabilityPresentation>
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

  private async command(action: "prompt" | "steer" | "cancel", path: string, body: Readonly<Record<string, string>>): Promise<ActionResult> {
    try {
      const capability = await this.input.capabilityIssuer.issue(action)
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
}

function decodeActionResult(status: number, value: unknown): ActionResult {
  if (!isRecord(value) || typeof value.ok !== "boolean") return { ok: false, reason: "uncertain" }
  if (value.ok === true && (value.state === "dispatched" || value.state === "already_recorded")) return { ok: true, state: value.state }
  if (value.ok === false && typeof value.reason === "string" && isFailure(value.reason)) return { ok: false, reason: value.reason }
  return status === 401 ? { ok: false, reason: "invalid" } : { ok: false, reason: "uncertain" }
}

function isFailure(value: string): value is Extract<ActionResult, { ok: false }>["reason"] {
  return value === "action_mismatch" || value === "actor_mismatch" || value === "audience_mismatch" || value === "conversation_mismatch" || value === "expired" || value === "invalid" || value === "replayed" || value === "invalid_request" || value === "persistence_conflict" || value === "terminal" || value === "uncertain"
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}
