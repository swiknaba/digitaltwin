import { bridgeActorId, commanderConversationId, streamCursor, type CommanderRuntime } from "./contract.ts"
import { CommanderBridgeController } from "./controller.ts"
import { EphemeralTestAuthority } from "./ephemeral-test-authority.ts"
import { CommanderMainProcessPanel } from "./main-process-panel.ts"
import { CommanderMainProcessTransport } from "./main-process-transport.ts"
import { CommanderBridgeHttpService } from "./http-service.ts"
import { InMemoryConversationStore } from "./in-memory-store.ts"
import { createCommanderBridgeNodeListener } from "./node-http-listener.ts"
import { RuntimeEventIngress } from "./runtime-event-ingress.ts"
import type { HostOperatorBootstrap } from "./host-bootstrap.ts"

type HarnessRuntime = CommanderRuntime & Readonly<{ prompts: string[]; steers: string[]; cancels: number }>

export type EphemeralDesktopHarness = Readonly<{
  bootstrap: HostOperatorBootstrap
  panel: CommanderMainProcessPanel
  runtime: HarnessRuntime
  publish(text: string): Promise<void>
  close(): Promise<void>
}>

/**
 * Desktop-only local acceptance harness. It is enabled only by the desktop's
 * explicit test switch, uses a loopback listener plus random in-memory proofs,
 * and is never an operator identity or production credential source.
 */
export async function createEphemeralDesktopHarness(): Promise<EphemeralDesktopHarness> {
  const actorId = bridgeActorId("desktop-harness")
  const conversationId = commanderConversationId("commander:desktop-harness")
  const now = () => new Date()
  let activeTurn: string | undefined
  let nextCursor = 1
  let publishRuntimeEvent: (text: string) => Promise<void> = async () => {
    throw new Error("Commander harness runtime started before its event ingress")
  }
  const runtime = createRuntime((input) => {
    activeTurn = input.turnId
    setTimeout(() => { void publishRuntimeEvent(`stream: ${input.text}`) }, 0)
  })
  const authority = new EphemeralTestAuthority({ actorId, conversationId, now })
  const controller = new CommanderBridgeController({ actorId, conversationId, runtime, store: new InMemoryConversationStore(), verifier: authority, now })
  const ingress = new RuntimeEventIngress({ controller, conversationId, authenticator: authority, now })
  const listener = createCommanderBridgeNodeListener(new CommanderBridgeHttpService(controller))
  await new Promise<void>((resolve, reject) => listener.once("error", reject).listen(0, "127.0.0.1", resolve))
  const address = listener.address()
  if (!address || typeof address === "string") throw new Error("Commander harness did not bind a loopback port")
  const transport = new CommanderMainProcessTransport({ baseUrl: `http://127.0.0.1:${address.port}`, capabilityIssuer: authority, fetch: { fetch } })
  const panel = new CommanderMainProcessPanel(transport)
  publishRuntimeEvent = async (text) => {
    if (!activeTurn) throw new Error("Commander harness has no active turn")
    const cursor = streamCursor(nextCursor)
    const result = await ingress.deliver(authority.issueRuntimeEventProof(), {
      conversationId,
      turnId: activeTurn,
      cursor,
      deliveryId: `harness-${nextCursor}`,
      kind: "delta",
      text,
    })
    if (!result.ok) throw new Error("Commander harness rejected its runtime event")
    nextCursor++
  }

  return {
    bootstrap: { createPanel: () => panel },
    panel,
    runtime,
    publish: publishRuntimeEvent,
    close: () => new Promise<void>((resolve, reject) => listener.close((error) => error ? reject(error) : resolve())),
  }
}

function createRuntime(onPrompt: (input: Parameters<CommanderRuntime["prompt"]>[0]) => void): HarnessRuntime {
  const prompts: string[] = []
  const steers: string[] = []
  let cancels = 0
  return {
    prompts,
    steers,
    get cancels() { return cancels },
    async prompt(input) { prompts.push(input.text); onPrompt(input); return { state: "accepted", turnId: input.turnId } },
    async steer(input) { steers.push(input.text) },
    async cancel() { cancels++; return "acknowledged" },
  }
}
