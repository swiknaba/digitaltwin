import { CommanderDelegation } from "./delegation"
import { OpenCodeHttpGateway, ServiceRegistrationOpenCodeSidecar, staticOpenCodeSidecar } from "./gateway"
import { FileDelegationStore } from "./store"

type JSONRPCID = string | number | null
type JSONRPCRequest = Readonly<{ jsonrpc?: unknown; id?: JSONRPCID; method?: unknown; params?: unknown }>

const root = new URL("../..", import.meta.url).pathname
const stateFile = process.env.DIGITALTWIN_HERMES_DELEGATION_STATE ?? `${root}local/hermes/commander-delegation-state.json`
const registrationFile = process.env.DIGITALTWIN_OPENCODE_SERVICE_REGISTRATION_FILE
const sidecar = registrationFile === undefined
  ? staticOpenCodeSidecar(new URL("http://127.0.0.1:3086"), undefined)
  : new ServiceRegistrationOpenCodeSidecar(registrationFile)
const delegation = new CommanderDelegation(
  new OpenCodeHttpGateway(sidecar),
  new FileDelegationStore(stateFile),
  process.env.DIGITALTWIN_HERMES_PROVENANCE_SUBJECT ?? "hermes-profile-local",
)

for await (const line of console) {
  if (!line.trim()) continue
  let request: JSONRPCRequest
  try {
    request = JSON.parse(line) as JSONRPCRequest
  } catch {
    respond(null, undefined, { code: -32700, message: "Parse error" })
    continue
  }
  if (request.jsonrpc !== "2.0" || typeof request.method !== "string") {
    respond(id(request), undefined, { code: -32600, message: "Invalid Request" })
    continue
  }
  try {
    const result = await dispatch(request.method, request.params)
    if (request.id !== undefined) respond(request.id, result)
  } catch (error) {
    if (request.id !== undefined) respond(request.id, undefined, { code: -32000, message: message(error) })
  }
}

async function dispatch(method: string, params: unknown): Promise<unknown> {
  if (method === "initialize") {
    return {
      protocolVersion: "2025-03-26",
      capabilities: { tools: { listChanged: false } },
      serverInfo: { name: "digitaltwin-commander-delegation", version: "1.0.0" },
    }
  }
  if (method === "notifications/initialized") return undefined
  if (method === "tools/list") return { tools: tools() }
  if (method === "tools/call") return call(params)
  throw new Error("Method not found.")
}

function tools(): readonly Readonly<Record<string, unknown>>[] {
  return [
    { name: "commander_list_projects", description: "List the existing OpenCode projects Commander may target. This operation never dispatches a prompt.", inputSchema: { type: "object", additionalProperties: false, properties: {} } },
    {
      name: "commander_create_project_session",
      description: "Create a normal project session, admit the supplied prompt, and return opaque follow-up references with Hermes MCP provenance. worker_model is an optional explicit OpenCode worker choice; it is not the Commander/Hermes model and must be enabled for the target project.",
      inputSchema: {
        type: "object",
        additionalProperties: false,
        required: ["project_id", "request_id", "text"],
        properties: {
          project_id: { type: "string" },
          request_id: { type: "string" },
          text: { type: "string" },
          worker_model: workerModelSchema(),
        },
      },
    },
    { name: "commander_read_agent", description: "Read a Commander-created session without dispatching a prompt. Use exactly one decision_id or session_id returned by create.", inputSchema: { type: "object", additionalProperties: false, properties: { decision_id: { type: "string" }, session_id: { type: "string" } } } },
    {
      name: "commander_continue_agent",
      description: "Continue a Commander-created session using a stable reference and request id. Use exactly one decision_id or session_id from create. worker_model optionally switches only this worker session before the next provider turn; it does not change project or Commander defaults.",
      inputSchema: {
        type: "object",
        additionalProperties: false,
        required: ["request_id", "text"],
        properties: {
          decision_id: { type: "string" },
          session_id: { type: "string" },
          request_id: { type: "string" },
          text: { type: "string" },
          worker_model: workerModelSchema(),
        },
      },
    },
  ]
}

async function call(params: unknown): Promise<unknown> {
  if (!object(params) || typeof params.name !== "string" || !object(params.arguments)) throw new Error("Invalid tool call parameters.")
  const args = params.arguments
  if (params.name === "commander_list_projects") return content(await delegation.listProjects())
  if (params.name === "commander_create_project_session") {
    const worker = workerModel(args)
    return content(await delegation.create({
      projectID: required(args, "project_id"),
      requestID: required(args, "request_id"),
      text: required(args, "text"),
      ...(worker === undefined ? {} : { workerModel: worker }),
    }))
  }
  if (params.name === "commander_read_agent") return content(await delegation.read(references(args)))
  if (params.name === "commander_continue_agent") {
    const worker = workerModel(args)
    return content(await delegation.continue({
      ...references(args),
      requestID: required(args, "request_id"),
      text: required(args, "text"),
      ...(worker === undefined ? {} : { workerModel: worker }),
    }))
  }
  throw new Error("Unknown Commander tool.")
}

function content(value: unknown): Readonly<{ content: readonly Readonly<{ type: "text"; text: string }>[] }> {
  return { content: [{ type: "text", text: JSON.stringify(value) }] }
}

function references(value: Record<string, unknown>): Readonly<{ decisionID?: string; sessionID?: string }> {
  const decisionID = optional(value, "decision_id")
  const sessionID = optional(value, "session_id")
  return { ...(decisionID === undefined ? {} : { decisionID }), ...(sessionID === undefined ? {} : { sessionID }) }
}

function required(value: Record<string, unknown>, field: string): string {
  const result = value[field]
  if (typeof result !== "string") throw new Error(`${field} is required.`)
  return result
}

function optional(value: Record<string, unknown>, field: string): string | undefined {
  const result = value[field]
  if (result === undefined) return undefined
  if (typeof result !== "string") throw new Error(`${field} must be a string.`)
  return result
}

function workerModel(value: Record<string, unknown>): Readonly<{ providerID: string; modelID: string; variant?: string }> | undefined {
  const candidate = value.worker_model
  if (candidate === undefined) return undefined
  if (!object(candidate) || typeof candidate.provider_id !== "string" || typeof candidate.model_id !== "string" || (candidate.variant !== undefined && typeof candidate.variant !== "string")) {
    throw new Error("worker_model must contain provider_id and model_id strings.")
  }
  return {
    providerID: candidate.provider_id,
    modelID: candidate.model_id,
    ...(candidate.variant === undefined ? {} : { variant: candidate.variant }),
  }
}

function workerModelSchema(): Readonly<Record<string, unknown>> {
  return {
    type: "object",
    additionalProperties: false,
    required: ["provider_id", "model_id"],
    properties: {
      provider_id: { type: "string" },
      model_id: { type: "string" },
      variant: { type: "string" },
    },
  }
}

function id(request: JSONRPCRequest): JSONRPCID { return request.id === undefined ? null : request.id }
function respond(idValue: JSONRPCID, result?: unknown, error?: Readonly<{ code: number; message: string }>): void {
  process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: idValue, ...(error ? { error } : { result }) })}\n`)
}
function object(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value) }
function message(error: unknown): string { return error instanceof Error ? error.message : "Commander MCP failed." }
