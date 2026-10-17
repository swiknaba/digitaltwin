import type { HermesEvent, HermesGateway, HermesModel, HermesRun } from "./contract"

type Fetch = typeof fetch

export class HermesGatewayClient implements HermesGateway {
  constructor(private readonly endpoint: URL, private readonly token: string, private readonly request: Fetch = fetch) {}

  capabilities(): Promise<unknown> { return this.json("/v1/capabilities") }
  models(): Promise<unknown> { return this.json("/api/model/options") }

  async setModel(model: HermesModel): Promise<void> {
    await this.json("/api/model/set", { method: "POST", body: JSON.stringify({ scope: "main", provider: model.provider, model: model.model }) })
  }

  async start(input: Readonly<{ text: string; sessionID?: string; model?: string; idempotencyKey: string }>): Promise<HermesRun> {
    const body = { input: input.text, ...(input.sessionID ? { session_id: input.sessionID } : {}), ...(input.model ? { model: input.model } : {}) }
    return run(await this.json("/v1/runs", { method: "POST", headers: { "Idempotency-Key": input.idempotencyKey }, body: JSON.stringify(body) }), input.sessionID)
  }

  async status(runID: string): Promise<HermesRun> { return run(await this.json(`/v1/runs/${encodeURIComponent(runID)}`), "") }
  async steer(runID: string, text: string): Promise<void> { await this.json(`/v1/runs/${encodeURIComponent(runID)}/steer`, { method: "POST", body: JSON.stringify({ input: text }) }) }
  async stop(runID: string): Promise<void> { await this.json(`/v1/runs/${encodeURIComponent(runID)}/stop`, { method: "POST" }) }

  async *events(runID: string, after?: number): AsyncIterable<HermesEvent> {
    const response = await this.request(new URL(`/v1/runs/${encodeURIComponent(runID)}/events`, this.endpoint), { headers: this.headers(after === undefined ? {} : { "Last-Event-ID": String(after) }) })
    if (!response.ok || !response.body) throw new Error(`Hermes event stream failed (${response.status}).`)
    const reader = response.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ""
    while (true) {
      const next = await reader.read()
      if (next.done) return
      buffer += decoder.decode(next.value, { stream: true })
      const frames = buffer.split("\n\n")
      buffer = frames.pop() ?? ""
      for (const frame of frames) {
        const line = frame.split("\n").find((item) => item.startsWith("data: "))
        if (!line) continue
        const value: unknown = JSON.parse(line.slice(6))
        if (!event(value)) throw new Error("Hermes event stream contained an invalid event.")
        yield value
      }
    }
  }

  private async json(path: string, init: RequestInit = {}): Promise<unknown> {
    const response = await this.request(new URL(path, this.endpoint), { ...init, headers: this.headers(init.headers), body: init.body })
    if (!response.ok) throw new Error(`Hermes request failed (${response.status}).`)
    return response.json()
  }

  private headers(extra: HeadersInit = {}): Headers {
    const headers = new Headers(extra)
    headers.set("Authorization", `Bearer ${this.token}`)
    headers.set("Content-Type", "application/json")
    return headers
  }
}

function run(value: unknown, submittedSessionID: string | undefined): HermesRun {
  if (!object(value) || typeof value.run_id !== "string" || typeof value.status !== "string") throw new Error("Hermes returned an incomplete run admission.")
  // Hermes admissions deliberately return only run_id/status.  The harness owns
  // the stable session ID and persists it before the first submission.
  return { runID: value.run_id, sessionID: submittedSessionID ?? "", status: value.status, ...(typeof value.model === "string" ? { model: value.model } : {}) }
}

function event(value: unknown): value is HermesEvent { return object(value) && typeof value.seq === "number" && typeof value.type === "string" && typeof value.run_id === "string" }
function object(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value) }
