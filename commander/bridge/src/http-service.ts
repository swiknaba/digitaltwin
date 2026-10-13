import type { CapabilityPresentation } from "./contract.ts"
import type { CommanderBridgeController } from "./controller.ts"

export type BridgeHttpRequest = Readonly<{
  method: "POST"
  path: "/v1/commander/open" | "/v1/commander/reconnect" | "/v1/commander/prompt" | "/v1/commander/steer" | "/v1/commander/cancel"
  authorization?: string
  body: unknown
}>

export type BridgeHttpResponse = Readonly<{ status: 200 | 400 | 401; body: unknown }>

/**
 * This is a parsed protocol service, not a network listener. A production listener
 * must bind privately, reject unknown methods/routes and cap body size. The desktop
 * main process obtains one short-lived proof per action and sends it as a header.
 */
export class CommanderBridgeHttpService {
  private readonly controller: CommanderBridgeController

  constructor(controller: CommanderBridgeController) {
    this.controller = controller
  }

  async handle(request: BridgeHttpRequest): Promise<BridgeHttpResponse> {
    const presentation = capability(request.authorization)
    if (!presentation) return { status: 401, body: { ok: false, reason: "invalid" } }
    if (request.path === "/v1/commander/open") return success(await this.controller.open(presentation))
    if (request.path === "/v1/commander/reconnect") return this.reconnect(presentation, request.body)
    if (request.path === "/v1/commander/prompt") return this.command(presentation, request.body, "prompt")
    if (request.path === "/v1/commander/steer") return this.command(presentation, request.body, "steer")
    return this.cancel(presentation, request.body)
  }

  private async reconnect(presentation: CapabilityPresentation, body: unknown): Promise<BridgeHttpResponse> {
    return success(await this.controller.reconnect(presentation, field(body, "after")))
  }

  private async command(presentation: CapabilityPresentation, body: unknown, action: "prompt" | "steer"): Promise<BridgeHttpResponse> {
    const requestId = field(body, "requestId")
    const text = field(body, "text")
    if (typeof requestId !== "string" || typeof text !== "string") return { status: 400, body: { ok: false, reason: "invalid_request" } }
    try {
      return success(action === "prompt" ? await this.controller.prompt(presentation, requestId, text) : await this.controller.steer(presentation, requestId, text))
    } catch { return { status: 400, body: { ok: false, reason: "invalid_request" } } }
  }

  private async cancel(presentation: CapabilityPresentation, body: unknown): Promise<BridgeHttpResponse> {
    const requestId = field(body, "requestId")
    if (typeof requestId !== "string") return { status: 400, body: { ok: false, reason: "invalid_request" } }
    try { return success(await this.controller.cancel(presentation, requestId)) } catch { return { status: 400, body: { ok: false, reason: "invalid_request" } } }
  }

}

function capability(authorization: string | undefined): CapabilityPresentation | undefined {
  if (!authorization?.startsWith("Bearer ")) return undefined
  const token = authorization.slice("Bearer ".length)
  return token.length > 0 && token.length <= 4096 ? { token } : undefined
}

function field(value: unknown, name: string): unknown {
  return isRecord(value) ? value[name] : undefined
}

function success(value: unknown): BridgeHttpResponse {
  return { status: 200, body: value }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}
