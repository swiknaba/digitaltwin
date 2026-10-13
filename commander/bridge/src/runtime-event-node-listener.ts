import { chmod, lstat, mkdir } from "node:fs/promises"
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http"
import { dirname } from "node:path"
import { decodeStreamEvent } from "./contract.ts"
import type { RuntimeEventIngress } from "./runtime-event-ingress.ts"

const route = "/v1/commander/runtime-events"
const maximumBodyBytes = 64 * 1024

/**
 * Runtime-only Unix-domain listener. It deliberately has a different socket and
 * route from the desktop action listener; a panel proof cannot reach this path.
 */
export function createRuntimeEventNodeListener(ingress: RuntimeEventIngress): Server {
  return createServer((request, response) => { void handle(ingress, request, response).catch(() => send(response, 500, { ok: false, reason: "internal" })) })
}

/** The operator creates the containing directory; an existing socket is never replaced. */
export async function listenRuntimeEventSocket(server: Server, path: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 })
  try {
    await lstat(path)
    throw new Error("Runtime event socket already exists")
  } catch (error: unknown) {
    if (!isMissingFile(error)) throw error
  }
  await new Promise<void>((resolve, reject) => {
    const failed = (error: Error) => reject(error)
    server.once("error", failed)
    server.listen(path, () => { server.off("error", failed); resolve() })
  })
  await chmod(path, 0o600)
}

async function handle(ingress: RuntimeEventIngress, request: IncomingMessage, response: ServerResponse): Promise<void> {
  if (request.method !== "POST") return send(response, 405, { ok: false, reason: "method_not_allowed" })
  if (new URL(request.url ?? "/", "http://localhost").pathname !== route) return send(response, 404, { ok: false, reason: "not_found" })
  if (!request.headers["content-type"]?.toLowerCase().startsWith("application/json")) return send(response, 400, { ok: false, reason: "invalid_content_type" })
  const presentation = capability(request.headers.authorization)
  if (!presentation) return send(response, 401, { ok: false, reason: "unauthenticated" })
  const body = await readJson(request)
  if (!body.ok) return send(response, body.status, { ok: false, reason: body.reason })
  const event = decodeStreamEvent(body.value)
  if (!event) return send(response, 400, { ok: false, reason: "invalid_event" })
  const result = await ingress.deliver(presentation, event)
  return send(response, result.ok ? 200 : result.reason === "unauthenticated" ? 401 : 400, result)
}

function capability(authorization: string | undefined): Readonly<{ token: string }> | undefined {
  if (!authorization?.startsWith("Bearer ")) return undefined
  const token = authorization.slice("Bearer ".length)
  return token.length > 0 && token.length <= 4096 ? { token } : undefined
}

async function readJson(request: IncomingMessage): Promise<Readonly<{ ok: true; value: unknown }> | Readonly<{ ok: false; status: 400 | 413; reason: "invalid_json" | "body_too_large" }>> {
  let size = 0; const chunks: Buffer[] = []
  for await (const chunk of request) { const buffer = Buffer.from(chunk); size += buffer.byteLength; if (size > maximumBodyBytes) return { ok: false, status: 413, reason: "body_too_large" }; chunks.push(buffer) }
  try { return { ok: true, value: JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown } } catch { return { ok: false, status: 400, reason: "invalid_json" } }
}

function send(response: ServerResponse, status: 200 | 400 | 401 | 404 | 405 | 413 | 500, body: unknown): void { response.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }); response.end(JSON.stringify(body)) }
function isMissingFile(error: unknown): error is NodeJS.ErrnoException { return typeof error === "object" && error !== null && "code" in error && error.code === "ENOENT" }
