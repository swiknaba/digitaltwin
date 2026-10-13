import { type BridgeRequestId, type CapabilityPresentation, type OpenCodeMessageProvenance } from "./contract.ts"
import type { CommanderBridgeController } from "./controller.ts"

export type ContinuationResult =
  | Readonly<{ ok: true; state: "continued" }>
  | Readonly<{ ok: false; reason: "invalid" | "missing" | "inaccessible" | "stale" | "unauthorized" | "request_conflict" | "uncertain" }>

/**
 * Trusted exact-session facade. Implementations must pass the idempotency key to
 * the pinned OpenCode client and answer reconciliation without title or agent
 * matching. This adapter has no renderer, HTTP, or bootstrap registration.
 */
export interface OpenCodeSessionClient {
  session(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible">
  message(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible">
  prompt(input: Readonly<{ provenance: OpenCodeMessageProvenance; text: string; idempotencyKey: string }>): Promise<"accepted" | "stale" | "missing" | "inaccessible" | "unknown">
  reconcile(input: Readonly<{ provenance: OpenCodeMessageProvenance; idempotencyKey: string }>): Promise<"accepted" | "unknown">
}

export class TrustedOpenCodeContinuation {
  private readonly input: Readonly<{ controller: CommanderBridgeController; client: OpenCodeSessionClient }>

  constructor(input: Readonly<{ controller: CommanderBridgeController; client: OpenCodeSessionClient }>) {
    this.input = input
  }

  async continue(input: Readonly<{ presentation: CapabilityPresentation; deliveryId: string; requestId: string; text: string }>): Promise<ContinuationResult> {
    const prepared = await this.input.controller.prepareContinuation(input.presentation, input.deliveryId, input.requestId, input.text)
    if (!prepared.ok) return { ok: false, reason: continuationFailure(prepared.reason) }
    if (prepared.state === "already_recorded") return { ok: true, state: "continued" }

    try {
      const session = await this.input.client.session(prepared.provenance)
      if (session !== "found") return this.reject(prepared.requestId, session)
      const message = await this.input.client.message(prepared.provenance)
      if (message !== "found") return this.reject(prepared.requestId, message)
      const prompted = await this.input.client.prompt({ provenance: prepared.provenance, text: input.text, idempotencyKey: prepared.idempotencyKey })
      if (prompted === "accepted") return this.complete(prepared.requestId)
      if (prompted !== "unknown") return this.reject(prepared.requestId, prompted)
    } catch {
      // An interrupted client call may have reached OpenCode; reconcile below.
    }
    return this.reconcile(prepared.requestId, prepared.provenance, prepared.idempotencyKey)
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

  private async reconcile(requestId: BridgeRequestId, provenance: OpenCodeMessageProvenance, idempotencyKey: string): Promise<ContinuationResult> {
    try {
      if (await this.input.client.reconcile({ provenance, idempotencyKey }) === "accepted") return this.complete(requestId)
    } catch {
      // The durable request remains uncertain; it must not be replayed.
    }
    await this.input.controller.settleContinuation(requestId, "uncertain")
    return { ok: false, reason: "uncertain" }
  }
}

function continuationFailure(reason: string): "invalid" | "missing" | "inaccessible" | "stale" | "unauthorized" | "request_conflict" | "uncertain" {
  if (reason === "missing" || reason === "inaccessible" || reason === "stale" || reason === "request_conflict" || reason === "uncertain") return reason
  if (reason === "invalid_request") return "invalid"
  return "unauthorized"
}
