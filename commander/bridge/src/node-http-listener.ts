import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http"
import type { BridgeHttpRequest, CommanderBridgeHttpService } from "./http-service.ts"

const maximumBodyBytes = 64 * 1024
const routes = ["/v1/commander/open", "/v1/commander/reconnect", "/v1/commander/prompt", "/v1/commander/steer", "/v1/commander/cancel"] as const
type BridgeRoute = (typeof routes)[number]

/**
 * Minimal Node listener for the private user-action API. Deployments must bind this
 * only to an operator-owned HTTPS endpoint or loopback address; runtime events use
 * RuntimeEventIngress instead of this public action surface.
 */
export function createCommanderBridgeNodeListener(service: CommanderBridgeHttpService): Server {
  return createServer((request, response) => { void handle(service, request, response) })
}

async function handle(service: CommanderBridgeHttpService, request: IncomingMessage, response: ServerResponse): Promise<void> {
  if (request.method !== "POST") return send(response, 405, { ok: false, reason: "method_not_allowed" })
  const route = routeFor(request.url)
  if (!route) return send(response, 404, { ok: false, reason: "not_found" })
  if (!request.headers["content-type"]?.toLowerCase().startsWith("application/json")) return send(response, 400, { ok: false, reason: "invalid_content_type" })
  const body = await readJson(request)
  if (!body.ok) return send(response, body.status, { ok: false, reason: body.reason })
  const authorization = request.headers.authorization
  const input: BridgeHttpRequest = authorization === undefined ? { method: "POST", path: route, body: body.value } : { method: "POST", path: route, authorization, body: body.value }
  try {
    const result = await service.handle(input)
    return send(response, result.status, result.body)
  } catch { return send(response, 500, { ok: false, reason: "internal" }) }
}

function routeFor(rawUrl: string | undefined): BridgeRoute | undefined {
  const pathname = new URL(rawUrl ?? "/", "http://localhost").pathname
  return routes.find((candidate) => candidate === pathname)
}

async function readJson(request: IncomingMessage): Promise<Readonly<{ ok: true; value: unknown }> | Readonly<{ ok: false; status: 400 | 413; reason: "invalid_json" | "body_too_large" }>> {
  let size = 0
  const chunks: Buffer[] = []
  for await (const chunk of request) {
    const buffer = Buffer.from(chunk)
    size += buffer.byteLength
    if (size > maximumBodyBytes) return { ok: false, status: 413, reason: "body_too_large" }
    chunks.push(buffer)
  }
  try { return { ok: true, value: JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown } } catch { return { ok: false, status: 400, reason: "invalid_json" } }
}

function send(response: ServerResponse, status: 200 | 400 | 401 | 404 | 405 | 413 | 500, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" })
  response.end(JSON.stringify(body))
}
