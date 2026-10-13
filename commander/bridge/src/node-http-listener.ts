import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http"
import { timingSafeEqual } from "node:crypto"
import type { BridgeHttpRequest, CommanderBridgeHttpService } from "./http-service.ts"
import { FileFutureTaskDeliveryStore, FutureTaskDeliveryService, type FutureTaskDeliveryStore } from "./future-task-delivery.ts"

const maximumBodyBytes = 64 * 1024
const routes = ["/v1/commander/open", "/v1/commander/reconnect", "/v1/commander/prompt", "/v1/commander/steer", "/v1/commander/cancel"] as const
type BridgeRoute = (typeof routes)[number]
const deliveriesRoute = "/private/future-tasks/deliveries"

export type FutureTaskListenerOptions = Readonly<{ identity: string; store: FutureTaskDeliveryStore }>

/**
 * Minimal Node listener for the private user-action API. Deployments must bind this
 * only to an operator-owned HTTPS endpoint or loopback address; runtime events use
 * RuntimeEventIngress instead of this public action surface.
 */
export function createCommanderBridgeNodeListener(service: CommanderBridgeHttpService, futureTasks?: FutureTaskListenerOptions): Server {
  const deliveries = futureTasks === undefined ? undefined : new FutureTaskDeliveryService({ store: futureTasks.store, publish: ({ deliveryKey, text }) => service.controller.appendFutureTask(deliveryKey, text) })
  return createServer((request, response) => { void handle(service, deliveries, futureTasks?.identity, request, response).catch(() => send(response, 500, { ok: false, reason: "internal" })) })
}

/** Operator bootstrap for the private delivery surface; identity and path stay outside project configuration. */
export function createOperatorCommanderBridgeNodeListener(service: CommanderBridgeHttpService, input: Readonly<{ futureTaskIdentity: string; futureTaskReceiptPath: string }>): Server {
  return createCommanderBridgeNodeListener(service, { identity: input.futureTaskIdentity, store: new FileFutureTaskDeliveryStore(input.futureTaskReceiptPath) })
}

async function handle(service: CommanderBridgeHttpService, deliveries: FutureTaskDeliveryService | undefined, identity: string | undefined, request: IncomingMessage, response: ServerResponse): Promise<void> {
  try {
    const path = new URL(request.url ?? "/", "http://localhost").pathname
    if (path === deliveriesRoute || path.startsWith(`${deliveriesRoute}/`)) return handleFutureTaskDelivery(deliveries, identity, path, request, response)
    if (request.method !== "POST") return send(response, 405, { ok: false, reason: "method_not_allowed" })
    const route = routeFor(request.url)
    if (!route) return send(response, 404, { ok: false, reason: "not_found" })
    if (!request.headers["content-type"]?.toLowerCase().startsWith("application/json")) return send(response, 400, { ok: false, reason: "invalid_content_type" })
    const body = await readJson(request)
    if (!body.ok) return send(response, body.status, { ok: false, reason: body.reason })
    const authorization = request.headers.authorization
    const input: BridgeHttpRequest = authorization === undefined ? { method: "POST", path: route, body: body.value } : { method: "POST", path: route, authorization, body: body.value }
    const result = await service.handle(input)
    return send(response, result.status, result.body)
  } catch { return send(response, 500, { ok: false, reason: "internal" }) }
}

async function handleFutureTaskDelivery(deliveries: FutureTaskDeliveryService | undefined, identity: string | undefined, path: string, request: IncomingMessage, response: ServerResponse): Promise<void> {
  if (!deliveries || !identity || !authorized(request.headers.authorization, identity)) return send(response, 401, { ok: false, reason: "unauthorized" })
  if (request.method === "GET") {
    const deliveryKey = decodeURIComponent(path.slice(`${deliveriesRoute}/`.length))
    if (!deliveryKey || path === deliveriesRoute) return send(response, 404, { ok: false, reason: "not_found" })
    const receipt = await deliveries.reconcile(deliveryKey)
    return send(response, 200, receipt === undefined ? {} : responseBody(receipt))
  }
  if (request.method !== "POST" || path !== deliveriesRoute) return send(response, 405, { ok: false, reason: "method_not_allowed" })
  if (!request.headers["content-type"]?.toLowerCase().startsWith("application/json")) return send(response, 400, { ok: false, reason: "invalid_content_type" })
  const body = await readJson(request)
  if (!body.ok) return send(response, body.status, { ok: false, reason: body.reason })
  const delivery = deliveryInput(body.value)
  if (!delivery) return send(response, 400, { ok: false, reason: "invalid_request" })
  try { return send(response, 200, responseBody(await deliveries.deliver(delivery))) } catch { return send(response, 400, { ok: false, reason: "invalid_request" }) }
}

function routeFor(rawUrl: string | undefined): BridgeRoute | undefined {
  const pathname = new URL(rawUrl ?? "/", "http://localhost").pathname
  return routes.find((candidate) => candidate === pathname)
}

function authorized(header: string | undefined, identity: string): boolean {
  const value = header?.startsWith("Bearer ") ? header.slice("Bearer ".length) : undefined
  if (!value) return false
  const received = Buffer.from(value)
  const expected = Buffer.from(identity)
  return received.byteLength === expected.byteLength && timingSafeEqual(received, expected)
}

function deliveryInput(value: unknown): Readonly<{ deliveryKey: string; taskId: string; text: string; references: readonly string[]; dueAt: string; timezone: string }> | undefined {
  if (!isRecord(value)) return undefined
  const deliveryKey = value.delivery_key; const taskId = value.task_id; const text = value.text; const references = value.references; const dueAt = value.due_at; const timezone = value.timezone
  if (typeof deliveryKey !== "string" || typeof taskId !== "string" || typeof text !== "string" || typeof dueAt !== "string" || typeof timezone !== "string" || !Array.isArray(references) || !references.every((item) => typeof item === "string")) return undefined
  return { deliveryKey, taskId, text, references, dueAt, timezone }
}

function responseBody(delivery: Readonly<{ deliveryKey: string; commanderItemId: string }>): Readonly<{ delivery_key: string; commander_item_id: string }> {
  return { delivery_key: delivery.deliveryKey, commander_item_id: delivery.commanderItemId }
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

function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value) }
