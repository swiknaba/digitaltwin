import { lstat, readFile } from "node:fs/promises"
import { basename, isAbsolute } from "node:path"
import type { CommanderAvailableModel, CommanderMessage, CommanderProject, CommanderSession, CommanderWorkerModel, Json, OpenCodeCommanderGateway } from "./contract"

type Fetch = typeof fetch
type OpenCodeSidecar = Readonly<{ endpoint: URL; password: string }>

export interface OpenCodeSidecarSource {
  readonly retryOnUnauthorized: boolean
  resolve(): Promise<OpenCodeSidecar>
}

export function staticOpenCodeSidecar(endpoint: URL, password: string | undefined): OpenCodeSidecarSource {
  assertLoopbackSidecar(endpoint)
  return {
    retryOnUnauthorized: false,
    resolve: async () => {
      if (!password) throw new Error("OpenCode service registration access is not configured. Authorize a supported registration file before using Commander project tools.")
      return { endpoint, password }
    },
  }
}

export class ServiceRegistrationOpenCodeSidecar implements OpenCodeSidecarSource {
  readonly retryOnUnauthorized = true

  constructor(
    private readonly registrationFile: string,
    private readonly request: Fetch = fetch,
  ) {
    const registrationName = basename(registrationFile)
    if (!isAbsolute(registrationFile) || (registrationName !== "service-local.json" && registrationName !== "service.json")) {
      throw new Error("OpenCode service registration must be an absolute service-local.json or service.json path.")
    }
  }

  async resolve(): Promise<OpenCodeSidecar> {
    const registration = await readRegistration(this.registrationFile)
    const endpoint = parseEndpoint(registration.url)
    const health = await this.request(new URL("/api/info", endpoint), {
      headers: { Authorization: basicAuthorization(registration.password) },
    })
    if (!health.ok) throw new Error("Registered OpenCode service is not ready.")
    const info = await health.json().catch(() => undefined)
    if (!object(info) || info.pid !== registration.pid || (registration.version !== undefined && info.version !== registration.version)) {
      throw new Error("Registered OpenCode service failed identity verification.")
    }
    return { endpoint, password: registration.password }
  }
}

export class OpenCodeHttpGateway implements OpenCodeCommanderGateway {
  constructor(
    private readonly sidecar: OpenCodeSidecarSource,
    private readonly request: Fetch = fetch,
  ) {}

  async listProjects(): Promise<readonly CommanderProject[]> {
    const body = await this.json("/api/project")
    if (!Array.isArray(body)) throw new Error("OpenCode returned an invalid project list.")
    return body.flatMap((item): CommanderProject[] => {
      if (!object(item) || typeof item.id !== "string" || typeof item.canonical !== "string") return []
      const fallback = item.canonical.split("/").filter(Boolean).at(-1) ?? item.canonical
      return [{ id: item.id, name: typeof item.name === "string" && item.name.trim() ? item.name : fallback, directory: item.canonical }]
    })
  }

  async listAvailableModels(directory: string): Promise<readonly CommanderAvailableModel[]> {
    const query = new URLSearchParams({ "location[directory]": directory })
    const response = await this.json(`/api/model/enabled?${query.toString()}`)
    if (!object(response) || !Array.isArray(response.data)) throw new Error("OpenCode returned an invalid model list.")
    return response.data.flatMap(availableModel)
  }

  async createSession(input: Readonly<{ id: string; directory: string; model: CommanderWorkerModel }>): Promise<CommanderSession> {
    return session(data(await this.json("/api/session", {
      method: "POST",
      body: JSON.stringify({
        id: input.id,
        location: { directory: input.directory },
        model: apiModel(input.model),
      }),
    }), "session"))
  }

  async selectSessionModel(input: Readonly<{ sessionID: string; model: CommanderWorkerModel }>): Promise<void> {
    await this.empty(`/api/session/${encodeURIComponent(input.sessionID)}/model`, {
      method: "POST",
      body: JSON.stringify({ model: apiModel(input.model) }),
    })
  }

  async prompt(input: Readonly<{ sessionID: string; messageID: string; text: string; metadata: Readonly<Record<string, Json>> }>): Promise<CommanderMessage> {
    const body = await this.json(`/api/session/${encodeURIComponent(input.sessionID)}/prompt`, {
      method: "POST",
      body: JSON.stringify({ id: input.messageID, text: input.text, metadata: input.metadata, resume: true }),
    })
    return message(data(body, "prompt admission"))
  }

  async waitSession(sessionID: string): Promise<void> {
    let response = await this.requestJson(await this.sidecar.resolve(), `/api/experimental/session/${encodeURIComponent(sessionID)}/wait`, { method: "POST" })
    if (response.status === 401 && this.sidecar.retryOnUnauthorized) response = await this.requestJson(await this.sidecar.resolve(), `/api/experimental/session/${encodeURIComponent(sessionID)}/wait`, { method: "POST" })
    if (response.ok) return
    if (response.status === 401) throw new Error("OpenCode sidecar authorization was rejected (401).")
    throw new Error(`OpenCode request failed (${response.status}).`)
  }

  async readSession(sessionID: string): Promise<CommanderSession> {
    return session(data(await this.json(`/api/session/${encodeURIComponent(sessionID)}`), "session"))
  }

  async readMessages(sessionID: string): Promise<readonly CommanderMessage[]> {
    const body = await this.json(`/api/session/${encodeURIComponent(sessionID)}/message?order=desc&limit=100`)
    if (!object(body) || !Array.isArray(body.data)) throw new Error("OpenCode returned invalid session messages.")
    return body.data.flatMap((item): CommanderMessage[] => {
      if (!object(item) || typeof item.id !== "string" || typeof item.type !== "string") return []
      const metadata = object(item.metadata) ? jsonRecord(item.metadata) : undefined
      const content = Array.isArray(item.content) ? item.content.flatMap(contentPart) : undefined
      const error = structuredError(item.error)
      const model = modelRef(item.model)
      return [{
        id: item.id,
        type: item.type,
        ...(typeof item.text === "string" ? { text: item.text } : {}),
        ...(model === undefined ? {} : { model }),
        ...(typeof item.finish === "string" ? { finish: item.finish } : {}),
        ...(error === undefined ? {} : { error }),
        ...(metadata ? { metadata } : {}),
        ...(content && content.length > 0 ? { content } : {}),
      }]
    })
  }

  private async json(path: string, init: RequestInit = {}): Promise<unknown> {
    let response = await this.requestJson(await this.sidecar.resolve(), path, init)
    if (response.status === 401 && this.sidecar.retryOnUnauthorized) response = await this.requestJson(await this.sidecar.resolve(), path, init)
    if (!response.ok) {
      if (response.status === 401) throw new Error("OpenCode sidecar authorization was rejected (401).")
      throw new Error(`OpenCode request failed (${response.status}).`)
    }
    return response.json()
  }

  private async empty(path: string, init: RequestInit): Promise<void> {
    let response = await this.requestJson(await this.sidecar.resolve(), path, init)
    if (response.status === 401 && this.sidecar.retryOnUnauthorized) response = await this.requestJson(await this.sidecar.resolve(), path, init)
    if (response.ok) return
    if (response.status === 401) throw new Error("OpenCode sidecar authorization was rejected (401).")
    throw new Error(`OpenCode request failed (${response.status}).`)
  }

  private async requestJson(sidecar: OpenCodeSidecar, path: string, init: RequestInit): Promise<Response> {
    const headers = new Headers(init.headers)
    headers.set("Authorization", basicAuthorization(sidecar.password))
    headers.set("Content-Type", "application/json")
    return this.request(new URL(path, sidecar.endpoint), { ...init, headers })
  }
}

function assertLoopbackSidecar(endpoint: URL): void {
  const loopback = endpoint.hostname === "127.0.0.1" || endpoint.hostname === "::1" || endpoint.hostname === "[::1]"
  if (endpoint.protocol !== "http:" || !loopback || endpoint.username || endpoint.password || endpoint.pathname !== "/" || endpoint.search || endpoint.hash) {
    throw new Error("OpenCode sidecar endpoint must be an http loopback origin.")
  }
}

type ServiceRegistration = Readonly<{
  url: string
  pid: number
  password: string
  version?: string
}>

async function readRegistration(path: string): Promise<ServiceRegistration> {
  const details = await lstat(path)
  if (!details.isFile() || details.isSymbolicLink()) throw new Error("OpenCode service registration must be a regular file.")
  if (process.platform !== "win32") {
    if ((details.mode & 0o077) !== 0) throw new Error("OpenCode service registration permissions must exclude group and other access.")
    if (details.uid !== currentUserID()) throw new Error("OpenCode service registration must be owned by the current user.")
  }
  let value: unknown
  try {
    value = JSON.parse(await readFile(path, "utf8"))
  } catch {
    throw new Error("OpenCode service registration is invalid.")
  }
  if (!object(value)) throw new Error("OpenCode service registration is invalid.")
  const url = value.url
  const pid = value.pid
  const password = value.password
  if (typeof url !== "string" || typeof pid !== "number" || !Number.isSafeInteger(pid) || pid <= 0 || typeof password !== "string" || !password) {
    throw new Error("OpenCode service registration is invalid.")
  }
  if (value.version !== undefined && typeof value.version !== "string") throw new Error("OpenCode service registration is invalid.")
  return { url, pid, password, ...(typeof value.version === "string" ? { version: value.version } : {}) }
}

function parseEndpoint(value: string): URL {
  try {
    const endpoint = new URL(value)
    if (endpoint.hostname === "0.0.0.0") endpoint.hostname = "127.0.0.1"
    assertLoopbackSidecar(endpoint)
    return endpoint
  } catch (error) {
    if (error instanceof Error && error.message === "OpenCode sidecar endpoint must be an http loopback origin.") throw error
    throw new Error("OpenCode service registration has an invalid endpoint.")
  }
}

function basicAuthorization(password: string): string {
  return `Basic ${Buffer.from(`opencode:${password}`).toString("base64")}`
}

function currentUserID(): number {
  const getuid = process.getuid
  if (getuid === undefined) throw new Error("OpenCode service registration ownership cannot be verified.")
  return getuid()
}

function session(value: unknown): CommanderSession {
  if (!object(value) || typeof value.id !== "string" || typeof value.projectID !== "string") throw new Error("OpenCode returned an invalid session.")
  return { id: value.id, projectID: value.projectID }
}

function message(value: unknown): CommanderMessage {
  if (!object(value) || typeof value.id !== "string" || typeof value.type !== "string") throw new Error("OpenCode returned an invalid prompt admission.")
  const payload = object(value.payload) ? value.payload : undefined
  const metadataSource = object(value.metadata) ? value.metadata : payload !== undefined && object(payload.metadata) ? payload.metadata : undefined
  const metadata = metadataSource === undefined ? undefined : jsonRecord(metadataSource)
  const content = Array.isArray(value.content) ? value.content.flatMap(contentPart) : undefined
  return {
    id: value.id,
    type: value.type,
    ...(typeof value.sessionID === "string" ? { sessionID: value.sessionID } : {}),
    ...(typeof value.text === "string" ? { text: value.text } : payload !== undefined && typeof payload.text === "string" ? { text: payload.text } : {}),
    ...(metadata ? { metadata } : {}),
    ...(content && content.length > 0 ? { content } : {}),
  }
}

function data(value: unknown, resource: string): Record<string, unknown> {
  if (!object(value) || !object(value.data)) throw new Error(`OpenCode returned an invalid ${resource} response.`)
  return value.data
}

function contentPart(value: unknown): Readonly<{ type: string; text?: string }>[] {
  if (!object(value) || typeof value.type !== "string") return []
  return [{ type: value.type, ...(typeof value.text === "string" ? { text: value.text } : {}) }]
}

function structuredError(value: unknown): Readonly<{ type: string; status?: number }> | undefined {
  if (!object(value) || typeof value.type !== "string") return undefined
  return { type: value.type, ...(typeof value.status === "number" ? { status: value.status } : {}) }
}

function modelRef(value: unknown): Readonly<{ providerID: string; modelID: string; variant?: string }> | undefined {
  if (!object(value) || typeof value.providerID !== "string" || typeof value.id !== "string") return undefined
  return {
    providerID: value.providerID,
    modelID: value.id,
    ...(typeof value.variant === "string" ? { variant: value.variant } : {}),
  }
}

function availableModel(value: unknown): CommanderAvailableModel[] {
  if (!object(value) || value.enabled !== true || typeof value.providerID !== "string" || typeof value.id !== "string") return []
  const variants = Array.isArray(value.variants)
    ? value.variants.flatMap((variant): string[] => object(variant) && typeof variant.id === "string" ? [variant.id] : [])
    : []
  return [{
    model: {
      providerID: value.providerID,
      modelID: value.id,
    },
    ...(typeof value.name === "string" && value.name.trim() ? { displayName: value.name } : {}),
    variants,
  }]
}

function apiModel(value: CommanderWorkerModel): Readonly<{ providerID: string; id: string; variant?: string }> {
  return {
    providerID: value.providerID,
    id: value.modelID,
    ...(value.variant === undefined ? {} : { variant: value.variant }),
  }
}

function object(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value) }
function jsonRecord(value: Record<string, unknown>): Readonly<Record<string, Json>> {
  const result: Record<string, Json> = {}
  for (const [key, item] of Object.entries(value)) if (json(item)) result[key] = item
  return result
}
function json(value: unknown): value is Json {
  if (value === null || typeof value === "boolean" || typeof value === "number" || typeof value === "string") return true
  if (Array.isArray(value)) return value.every(json)
  return object(value) && Object.values(value).every(json)
}
