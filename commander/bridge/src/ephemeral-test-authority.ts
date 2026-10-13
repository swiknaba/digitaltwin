import { randomUUID } from "node:crypto"
import type { CapabilityBinding, CapabilityDecision, CapabilityPresentation, CapabilityVerifier, CommanderConversationId, BridgeActorId } from "./contract.ts"
import type { MainProcessCapabilityIssuer } from "./main-process-transport.ts"
import type { RuntimeAuthentication, RuntimeEventAuthenticator } from "./runtime-event-ingress.ts"

type IssuedUserProof = Readonly<{ action: Parameters<MainProcessCapabilityIssuer["issue"]>[0]["action"]; binding?: CapabilityBinding; expiresAt: Date }>

/**
 * Deterministic local-test authority. It holds random proofs only in memory and is
 * intentionally unsuitable for production bootstrap or cross-process deployment.
 */
export class EphemeralTestAuthority implements CapabilityVerifier, MainProcessCapabilityIssuer, RuntimeEventAuthenticator {
  private readonly userProofs = new Map<string, IssuedUserProof>()
  private readonly runtimeProofs = new Set<string>()
  private readonly actorId: BridgeActorId
  private readonly conversationId: CommanderConversationId
  private readonly now: () => Date

  constructor(input: Readonly<{ actorId: BridgeActorId; conversationId: CommanderConversationId; now: () => Date }>) { this.actorId = input.actorId; this.conversationId = input.conversationId; this.now = input.now }

  async issue(input: Parameters<MainProcessCapabilityIssuer["issue"]>[0]): Promise<CapabilityPresentation> {
    const token = randomUUID()
    this.userProofs.set(token, { action: input.action, ...(input.binding === undefined ? {} : { binding: input.binding }), expiresAt: new Date(this.now().getTime() + 60_000) })
    return { token }
  }

  issueRuntimeEventProof(): CapabilityPresentation { const token = randomUUID(); this.runtimeProofs.add(token); return { token } }

  async consume(input: Parameters<CapabilityVerifier["consume"]>[0]): Promise<CapabilityDecision> {
    const proof = this.userProofs.get(input.presentation.token)
    this.userProofs.delete(input.presentation.token)
    if (!proof || proof.action !== input.action || !sameBinding(proof.binding, input.expectedBinding)) return { ok: false, reason: "invalid" }
    const issuedAt = this.now()
    return { ok: true, capability: { action: proof.action, actorId: this.actorId, audience: input.expectedAudience, conversationId: this.conversationId, issuedAt, expiresAt: proof.expiresAt, nonce: input.presentation.token, ...(proof.binding === undefined ? {} : { binding: proof.binding }) } }
  }

  async authenticate(input: Parameters<RuntimeEventAuthenticator["authenticate"]>[0]): Promise<RuntimeAuthentication> {
    const accepted = this.runtimeProofs.delete(input.presentation.token)
    return accepted && input.expectedConversationId === this.conversationId ? { ok: true, identity: { runtimeId: "commander-runtime", conversationId: this.conversationId } } : { ok: false }
  }
}

function sameBinding(left: CapabilityBinding | undefined, right: CapabilityBinding | undefined): boolean {
  return left === undefined && right === undefined || left !== undefined && right !== undefined && left.requestId === right.requestId && left.payloadDigest === right.payloadDigest
}
