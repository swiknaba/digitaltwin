import type { HermesEvent, HermesGateway, HermesRun } from "./contract"

type Fetch = typeof fetch

export class HermesGatewayClient implements HermesGateway {
  constructor(private readonly endpoint: URL, private readonly token: string, private readonly request: Fetch = fetch) {}

  capabilities() { return this.json("/v1/capabilities") }
  models() { return this.json("/api/model/options") }

  async start(input: Readonly<{ text: string; sessionID?: string; model?: string; idempotencyKey: string }>): Promise<HermesRun> {
    const body = { input: input.text, ...(input.sessionID ? { session_id: input.sessionID } : {}), ...(input.model ? { model: input.model } : {}) }
    const value = await this.json("/v1/runs", { method: "POST", headers: { "Idempotency-Key": input.idempotencyKey }, body: JSON.stringify(body) })
    return run(value)
  }

  status(runID: string): Promise<HermesRun> { return this.json(`/v1/runs/${encodeURIComponent(runID)}`).then(run) }
  async steer(runID: string, text: string) { await this.json(`/v1/runs/${encodeURIComponent(runID)}/steer`, { method: "POST", body: JSON.stringify({ input: text }) }) }
  async stop(runID: string) { await this.json(`/v1/runs/${encodeURIComponent(runID)}/stop`, { method: "POST" }) }

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

function run(value: unknown): HermesRun {
  if (!value || typeof value !== "object") throw new Error("Hermes returned an invalid run.")
  const item = value as Record<string, unknown>
  if (typeof item.run_id !== "string" || typeof item.session_id !== "string" || typeof item.status !== "string") throw new Error("Hermes returned an incomplete run.")
  return { runID: item.run_id, sessionID: item.session_id, status: item.status, ...(typeof item.model === "string" ? { model: item.model } : {}) }
}

function event(value: unknown): value is HermesEvent {
  return !!value && typeof value === "object" && typeof (value as Record<string, unknown>).seq === "number" && typeof (value as Record<string, unknown>).type === "string" && typeof (value as Record<string, unknown>).run_id === "string"
}
