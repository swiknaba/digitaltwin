import { createHash } from "node:crypto"
import { type OpenCodeMessageProvenance } from "./contract.ts"

export type ContinuationResult =
  | Readonly<{ ok: true; state: "continued" }>
  | Readonly<{ ok: false; reason: "invalid" | "missing" | "inaccessible" | "stale" | "request_conflict" | "uncertain" }>

/**
 * Ordinary exact-session continuation. OpenCode's standard authenticated session
 * API remains the authority; `fromCommander` is provenance only, never privilege.
 */
export interface OpenCodeSessionClient {
  session(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible" | "unknown">
  message(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible" | "unknown">
  prompt(input: Readonly<{ provenance: OpenCodeMessageProvenance; inputId: string; text: string; requestDigest: string; metadata: Readonly<{ fromCommander: true; commanderRequestDigest: string }> }>): Promise<"accepted" | "stale" | "missing" | "inaccessible" | "unknown">
}

/** Minimal structural fetch boundary supplied by the already-authenticated OpenCode client. */
export interface OpenCodeSessionFetch {
  fetch(input: string, init?: Readonly<{ method?: string; headers?: Readonly<Record<string, string>>; body?: string }>): Promise<Readonly<{ status: number; json: () => Promise<unknown> }>>
}

/** Calls the pinned OpenCode v2.0.27 session API without adding an auth scheme. */
export class OpenCodeHttpSessionClient implements OpenCodeSessionClient {
  private readonly input: Readonly<{ origin: string; runtimeId: string; fetch: OpenCodeSessionFetch }>

  constructor(input: Readonly<{ origin: string; runtimeId: string; fetch: OpenCodeSessionFetch }>) {
    this.input = { ...input, origin: new URL(input.origin).origin }
  }

  async session(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible" | "unknown"> {
    return this.get(input, `/api/session/${encodeURIComponent(input.sessionId)}`)
  }

  async message(input: OpenCodeMessageProvenance): Promise<"found" | "missing" | "inaccessible" | "unknown"> {
    return this.get(input, `/api/session/${encodeURIComponent(input.sessionId)}/message/${encodeURIComponent(input.messageId)}`)
  }

  async prompt(input: Readonly<{ provenance: OpenCodeMessageProvenance; inputId: string; text: string; requestDigest: string; metadata: Readonly<{ fromCommander: true; commanderRequestDigest: string }> }>): Promise<"accepted" | "stale" | "missing" | "inaccessible" | "unknown"> {
    if (input.provenance.runtimeId !== this.input.runtimeId) return "inaccessible"
    const response = await this.input.fetch.fetch(`${this.input.origin}/api/session/${encodeURIComponent(input.provenance.sessionId)}/prompt`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ id: input.inputId, text: input.text, metadata: input.metadata, resume: true }),
    })
    if (response.status === 200) return "accepted"
    if (response.status === 404) return "missing"
    if (response.status === 401 || response.status === 403) return "inaccessible"
    if (response.status === 400) return "stale"
    if (response.status === 409) return await this.admitted(input)
    return "unknown"
  }

  private async admitted(input: Readonly<{ provenance: OpenCodeMessageProvenance; inputId: string; requestDigest: string }>): Promise<"accepted" | "stale" | "missing" | "inaccessible" | "unknown"> {
    const path = "/api/session/" + encodeURIComponent(input.provenance.sessionId) + "/message/" + encodeURIComponent(input.inputId)
    const response = await this.input.fetch.fetch(this.input.origin + path)
    if (response.status === 404) return "stale"
    if (response.status === 401 || response.status === 403) return "inaccessible"
    if (response.status < 200 || response.status > 299) return "unknown"
    try {
      return matchingAdmission(await response.json(), input) ? "accepted" : "stale"
    } catch {
      return "unknown"
    }
  }

  private async get(input: OpenCodeMessageProvenance, path: string): Promise<"found" | "missing" | "inaccessible" | "unknown"> {
    if (input.runtimeId !== this.input.runtimeId) return "inaccessible"
    const response = await this.input.fetch.fetch(`${this.input.origin}${path}`)
    if (response.status === 200) return "found"
    if (response.status === 404) return "missing"
    if (response.status === 401 || response.status === 403) return "inaccessible"
    return "unknown"
  }
}

export class OpenCodeSessionContinuation {
  private readonly client: OpenCodeSessionClient

  constructor(input: Readonly<{ client: OpenCodeSessionClient }>) {
    this.client = input.client
  }

  async continue(input: Readonly<{ provenance: OpenCodeMessageProvenance; requestId: string; text: string }>): Promise<ContinuationResult> {
    if (!validRequest(input)) return { ok: false, reason: "invalid" }
    const inputId = continuationInputId(input)
    const requestDigest = createHash("sha256").update(input.text, "utf8").digest("hex")

    try {
      const session = await this.client.session(input.provenance)
      if (session !== "found") return session === "unknown" ? { ok: false, reason: "uncertain" } : { ok: false, reason: session }
      const message = await this.client.message(input.provenance)
      if (message !== "found") return message === "unknown" ? { ok: false, reason: "uncertain" } : { ok: false, reason: message }
      const prompted = await this.client.prompt({ provenance: input.provenance, inputId, text: input.text, requestDigest, metadata: { fromCommander: true, commanderRequestDigest: requestDigest } })
      if (prompted === "accepted") return { ok: true, state: "continued" }
      if (prompted !== "unknown") return { ok: false, reason: prompted }
    } catch {
      // A standard OpenCode retry uses the same durable input ID.
    }
    return { ok: false, reason: "uncertain" }
  }
}

function validRequest(input: Readonly<{ provenance: OpenCodeMessageProvenance; requestId: string; text: string }>): boolean {
  return input.requestId.length > 0 && input.requestId.length <= 256 && input.text.trim().length > 0 && input.text.length <= 16_000
}

function continuationInputId(input: Readonly<{ provenance: OpenCodeMessageProvenance; requestId: string; text: string }>): string {
  // Body is deliberately excluded. Reusing a request id with different text
  // addresses the same OpenCode input and is rejected on conflict.
  const material = [input.provenance.runtimeId, input.provenance.projectId, input.provenance.sessionId, input.provenance.messageId, input.requestId].join("\n")
  return `msg_commander_${createHash("sha256").update(material, "utf8").digest("hex")}`
}

function matchingAdmission(value: unknown, input: Readonly<{ inputId: string; requestDigest: string }>): boolean {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false
  const record = value as Readonly<Record<string, unknown>>
  if (record.id !== input.inputId) return false
  const metadata = record.metadata
  return typeof metadata === "object" && metadata !== null && !Array.isArray(metadata)
    && (metadata as Readonly<Record<string, unknown>>).fromCommander === true
    && (metadata as Readonly<Record<string, unknown>>).commanderRequestDigest === input.requestDigest
}
