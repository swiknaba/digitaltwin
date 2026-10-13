import type { ApplyResult, CapabilityPresentation, CommanderConversationId, StreamEvent } from "./contract.ts"
import type { CommanderBridgeController } from "./controller.ts"

export type RuntimeIdentity = Readonly<{ runtimeId: "commander-runtime"; conversationId: CommanderConversationId }>
export type RuntimeAuthentication = Readonly<{ ok: true; identity: RuntimeIdentity }> | Readonly<{ ok: false }>

/** A separate runtime-owned channel; it does not accept desktop user capabilities. */
export interface RuntimeEventAuthenticator {
  authenticate(input: Readonly<{ presentation: CapabilityPresentation; expectedConversationId: CommanderConversationId; now: Date }>): Promise<RuntimeAuthentication>
}

export class RuntimeEventIngress {
  private readonly input: Readonly<{ controller: CommanderBridgeController; conversationId: CommanderConversationId; authenticator: RuntimeEventAuthenticator; now: () => Date }>

  constructor(input: Readonly<{ controller: CommanderBridgeController; conversationId: CommanderConversationId; authenticator: RuntimeEventAuthenticator; now: () => Date }>) { this.input = input }

  async deliver(presentation: CapabilityPresentation, event: StreamEvent): Promise<ApplyResult | Readonly<{ ok: false; reason: "unauthenticated" }>> {
    const authenticated = await this.input.authenticator.authenticate({ presentation, expectedConversationId: this.input.conversationId, now: this.input.now() })
    if (!authenticated.ok || authenticated.identity.runtimeId !== "commander-runtime" || authenticated.identity.conversationId !== this.input.conversationId) return { ok: false, reason: "unauthenticated" }
    return this.input.controller.apply(event)
  }
}
