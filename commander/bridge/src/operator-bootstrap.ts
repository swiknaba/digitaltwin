import type { BridgeActorId, CapabilityAction, CapabilityBinding, CapabilityPresentation, CommanderConversationId } from "./contract.ts"
import { CommanderMainProcessTransport, type MainProcessCapabilityIssuer, type MainProcessFetch } from "./main-process-transport.ts"

/** Values supplied only by the operator-owned desktop bootstrap, never by a panel. */
export type OperatorDesktopIdentity = Readonly<{ actorId: BridgeActorId; conversationId: CommanderConversationId }>

/**
 * Boundary for the deployment's short-lived proof exchange. Its implementation owns
 * OS-profile/remote identity verification and any credential material outside Git.
 */
export interface OperatorCapabilityExchange {
  issue(input: Readonly<{ audience: "commander-bridge"; actorId: BridgeActorId; conversationId: CommanderConversationId; action: CapabilityAction; binding?: CapabilityBinding }>): Promise<CapabilityPresentation>
}

/** Main-process-only issuer that closes over an already-verified operator identity. */
export class OperatorMainProcessCapabilityIssuer implements MainProcessCapabilityIssuer {
  private readonly identity: OperatorDesktopIdentity
  private readonly exchange: OperatorCapabilityExchange

  constructor(input: Readonly<{ identity: OperatorDesktopIdentity; exchange: OperatorCapabilityExchange }>) { this.identity = input.identity; this.exchange = input.exchange }

  async issue(input: Parameters<MainProcessCapabilityIssuer["issue"]>[0]): Promise<CapabilityPresentation> {
    return this.exchange.issue({ audience: "commander-bridge", actorId: this.identity.actorId, conversationId: this.identity.conversationId, action: input.action, ...(input.binding === undefined ? {} : { binding: input.binding }) })
  }
}

/** Creates the desktop-only transport after operator bootstrap has verified identity. */
export function createOperatorMainProcessTransport(input: Readonly<{ bridgeOrigin: string; identity: OperatorDesktopIdentity; exchange: OperatorCapabilityExchange; fetch: MainProcessFetch }>): CommanderMainProcessTransport {
  return new CommanderMainProcessTransport({ baseUrl: input.bridgeOrigin, capabilityIssuer: new OperatorMainProcessCapabilityIssuer({ identity: input.identity, exchange: input.exchange }), fetch: input.fetch })
}
