import type { CommanderMessage, CommanderProject, CommanderSession, Json, OpenCodeCommanderGateway } from "./contract"

type Fetch = typeof fetch

export class OpenCodeHttpGateway implements OpenCodeCommanderGateway {
  constructor(
    private readonly endpoint: URL,
    private readonly sidecarPassword: string | undefined,
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

  async createSession(input: Readonly<{ id: string; directory: string }>): Promise<CommanderSession> {
    return session(data(await this.json("/api/session", { method: "POST", body: JSON.stringify({ id: input.id, location: { directory: input.directory } }) }), "session"))
  }

  async prompt(input: Readonly<{ sessionID: string; messageID: string; text: string; metadata: Readonly<Record<string, Json>> }>): Promise<CommanderMessage> {
    const body = await this.json(`/api/session/${encodeURIComponent(input.sessionID)}/prompt`, {
      method: "POST",
      body: JSON.stringify({ id: input.messageID, text: input.text, metadata: input.metadata, resume: true }),
    })
    return message(data(body, "prompt admission"))
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
      return [{
        id: item.id,
        type: item.type,
        ...(typeof item.text === "string" ? { text: item.text } : {}),
        ...(metadata ? { metadata } : {}),
        ...(content && content.length > 0 ? { content } : {}),
      }]
    })
  }

  private async json(path: string, init: RequestInit = {}): Promise<unknown> {
    if (!this.sidecarPassword) {
      throw new Error("OpenCode sidecar authorization is not configured. Set DIGITALTWIN_OPENCODE_SIDECAR_PASSWORD only after the owner approves this bridge.")
    }
    const headers = new Headers(init.headers)
    headers.set("Authorization", `Basic ${Buffer.from(`opencode:${this.sidecarPassword}`).toString("base64")}`)
    headers.set("Content-Type", "application/json")
    const response = await this.request(new URL(path, this.endpoint), { ...init, headers })
    if (!response.ok) {
      if (response.status === 401) throw new Error("OpenCode sidecar authorization was rejected (401).")
      throw new Error(`OpenCode request failed (${response.status}).`)
    }
    return response.json()
  }
}

function session(value: unknown): CommanderSession {
  if (!object(value) || typeof value.id !== "string" || typeof value.projectID !== "string") throw new Error("OpenCode returned an invalid session.")
  return { id: value.id, projectID: value.projectID }
}

function message(value: unknown): CommanderMessage {
  if (!object(value) || typeof value.id !== "string" || typeof value.type !== "string") throw new Error("OpenCode returned an invalid prompt admission.")
  const metadata = object(value.metadata) ? jsonRecord(value.metadata) : undefined
  const content = Array.isArray(value.content) ? value.content.flatMap(contentPart) : undefined
  return {
    id: value.id,
    type: value.type,
    ...(typeof value.text === "string" ? { text: value.text } : {}),
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
