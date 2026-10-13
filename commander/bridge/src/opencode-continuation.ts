import { createHash } from "node:crypto"
import { bridgeRequestId, capabilityPayloadDigest, type CapabilityPresentation, type CapabilityVerifier, type CommanderConversationId, type OpenCodeMessageProvenance } from "./contract.ts"
import type { CommanderBridgeController } from "./controller.ts"

export type ContinuationResult =
  | Readonly<{ ok: true; state: "continued" }>
  | Readonly<{ ok: false; reason: "invalid" | "missing" | "inaccessible" | "stale" | "unauthorized" }>

/** Trusted adapter for exact OpenCode continuation; no renderer or HTTP route mounts this class. */
export interface OpenCodeSessionClient {
  session(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible">
  message(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible">
  prompt(input: Readonly<{ provenance: OpenCodeMessageProvenance; text: string }>): Promise<"accepted" | "stale" | "missing" | "inaccessible">
}

export class TrustedOpenCodeContinuation {
  private readonly input: Readonly<{ controller: CommanderBridgeController; verifier: CapabilityVerifier; conversationId: CommanderConversationId; client: OpenCodeSessionClient; now: () => Date }>

  constructor(input: Readonly<{ controller: CommanderBridgeController; verifier: CapabilityVerifier; conversationId: CommanderConversationId; client: OpenCodeSessionClient; now: () => Date }>) {
    this.input = input
  }

  async continue(input: Readonly<{ presentation: CapabilityPresentation; deliveryId: string; requestId: string; text: string }>): Promise<ContinuationResult> {
    if (!valid(input.deliveryId) || !valid(input.requestId) || !valid(input.text)) return { ok: false, reason: "invalid" }
    const provenance = await this.input.controller.provenanceForDelivery(input.deliveryId)
    if (!provenance) return { ok: false, reason: "missing" }
    let requestId
    try { requestId = bridgeRequestId(input.requestId) } catch { return { ok: false, reason: "invalid" } }
    const binding = capabilityPayloadDigest(createHash("sha256").update(JSON.stringify([input.deliveryId, provenance, input.requestId, input.text])).digest("hex"))
    const decision = await this.input.verifier.consume({ action: "continue", expectedAudience: "commander-bridge", expectedConversationId: this.input.conversationId, expectedBinding: { requestId, payloadDigest: binding }, presentation: input.presentation, now: this.input.now() })
    if (!decision.ok) return { ok: false, reason: "unauthorized" }
    const session = await this.input.client.session(provenance)
    if (session !== "found") return { ok: false, reason: session }
    const message = await this.input.client.message(provenance)
    if (message !== "found") return { ok: false, reason: message }
    const prompted = await this.input.client.prompt({ provenance, text: input.text })
    return prompted === "accepted" ? { ok: true, state: "continued" } : { ok: false, reason: prompted }
  }
}

function valid(value: string): boolean { return value.trim().length > 0 && value.length <= 16_000 }
