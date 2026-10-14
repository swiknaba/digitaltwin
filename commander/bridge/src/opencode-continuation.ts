import { type BridgeRequestId, type OpenCodeMessageProvenance } from "./contract.ts"
import type { CommanderBridgeController } from "./controller.ts"

export type ContinuationResult =
  | Readonly<{ ok: true; state: "continued" }>
  | Readonly<{ ok: false; reason: "invalid" | "missing" | "inaccessible" | "stale" | "request_conflict" | "uncertain" }>

/**
 * Ordinary exact-session continuation. OpenCode's standard authenticated session
 * API remains the authority; `fromCommander` is provenance only, never privilege.
 */
export interface OpenCodeSessionClient {
  session(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible">
  message(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible">
  prompt(input: Readonly<{ provenance: OpenCodeMessageProvenance; inputId: string; text: string; metadata: Readonly<{ fromCommander: true }> }>): Promise<"accepted" | "stale" | "missing" | "inaccessible" | "unknown">
}

/** Minimal structural fetch boundary supplied by the already-authenticated OpenCode client. */
export interface OpenCodeSessionFetch {
  fetch(input: string, init?: Readonly<{ method?: string; headers?: Readonly<Record<string, string>>; body?: string }>): Promise<Readonly<{ status: number }>>
}

/** Calls the pinned OpenCode v2.0.27 session API without adding an auth scheme. */
export class OpenCodeHttpSessionClient implements OpenCodeSessionClient {
  private readonly input: Readonly<{ origin: string; runtimeId: string; fetch: OpenCodeSessionFetch }>

  constructor(input: Readonly<{ origin: string; runtimeId: string; fetch: OpenCodeSessionFetch }>) {
    this.input = { ...input, origin: new URL(input.origin).origin }
  }

  async session(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible"> {
    return this.get(input, `/api/session/${encodeURIComponent(input.sessionId)}`)
  }

  async message(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible"> {
    return this.get(input, `/api/session/${encodeURIComponent(input.sessionId)}/message/${encodeURIComponent(input.messageId)}`)
  }

  async prompt(input: Readonly<{ provenance: OpenCodeMessageProvenance; inputId: string; text: string; metadata: Readonly<{ fromCommander: true }> }>): Promise<"accepted" | "stale" | "missing" | "inaccessible" | "unknown"> {
    if (input.provenance.runtimeId !== this.input.runtimeId) return "inaccessible"
    const response = await this.input.fetch.fetch(`${this.input.origin}/api/session/${encodeURIComponent(input.provenance.sessionId)}/prompt`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id: input.inputId, text: input.text, metadata: input.metadata, resume: true }),
    })
    if (response.status === 200) return "accepted"
    if (response.status === 404) return "missing"
    if (response.status === 401 || response.status === 403) return "inaccessible"
    if (response.status === 400 || response.status === 409) return "stale"
    return "unknown"
  }

  private async get(input: OpenCodeMessageProvenance, path: string): Promise<"found" | "missing" | "inaccessible"> {
    if (input.runtimeId !== this.input.runtimeId) return "inaccessible"
    const response = await this.input.fetch.fetch(`${this.input.origin}${path}`)
    if (response.status === 200) return "found"
    if (response.status === 404) return "missing"
    return "inaccessible"
  }
}

export class OpenCodeSessionContinuation {
  private readonly input: Readonly<{ controller: CommanderBridgeController; client: OpenCodeSessionClient }>

  constructor(input: Readonly<{ controller: CommanderBridgeController; client: OpenCodeSessionClient }>) {
    this.input = input
  }

  async continue(input: Readonly<{ deliveryId: string; requestId: string; text: string }>): Promise<ContinuationResult> {
    const prepared = await this.input.controller.prepareContinuation(input.deliveryId, input.requestId, input.text)
    if (!prepared.ok) return { ok: false, reason: continuationFailure(prepared.reason) }
    if (prepared.state === "already_recorded") return { ok: true, state: "continued" }

    try {
      const session = await this.input.client.session(prepared.provenance)
      if (session !== "found") return this.reject(prepared.requestId, session)
      const message = await this.input.client.message(prepared.provenance)
      if (message !== "found") return this.reject(prepared.requestId, message)
      const prompted = await this.input.client.prompt({ provenance: prepared.provenance, inputId: prepared.inputId, text: input.text, metadata: { fromCommander: true } })
      if (prompted === "accepted") return this.complete(prepared.requestId)
      if (prompted !== "unknown") return this.reject(prepared.requestId, prompted)
    } catch {
      // A standard OpenCode retry uses the same durable input ID.
    }
    await this.input.controller.settleContinuation(prepared.requestId, "uncertain")
    return { ok: false, reason: "uncertain" }
  }

  private async complete(requestId: BridgeRequestId): Promise<ContinuationResult> {
    return await this.input.controller.settleContinuation(requestId, "continued")
      ? { ok: true, state: "continued" }
      : { ok: false, reason: "uncertain" }
  }

  private async reject(requestId: BridgeRequestId, reason: "missing" | "inaccessible" | "stale"): Promise<ContinuationResult> {
    return await this.input.controller.settleContinuation(requestId, reason)
      ? { ok: false, reason }
      : { ok: false, reason: "uncertain" }
  }

}

function continuationFailure(reason: string): "invalid" | "missing" | "inaccessible" | "stale" | "request_conflict" | "uncertain" {
  if (reason === "missing" || reason === "inaccessible" || reason === "stale" || reason === "request_conflict" || reason === "uncertain") return reason
  return "invalid"
}
