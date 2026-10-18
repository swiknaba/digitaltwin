import type { HermesEvent, HermesGateway, HermesHistoryMessage, HermesModelOption, HermesRun } from "./contract"

type Fetch = typeof fetch

export class HermesGatewayClient implements HermesGateway {
  constructor(private readonly endpoint: URL, private readonly token: string, private readonly request: Fetch = fetch) {}

  capabilities(): Promise<unknown> { return this.json("/v1/capabilities") }
  async models(): Promise<readonly HermesModelOption[]> { return modelOptions(await this.json("/api/model/options")) }

  async start(input: Readonly<{ text: string; sessionID?: string; model: Readonly<{ provider: string; model: string }>; idempotencyKey: string }>): Promise<HermesRun> {
    // `hermes gateway` does not implement dashboard-only /api/model/set. Submit
    // the durable Commander choice on every run instead, and require its router
    // to lock the exact provider/model rather than silently using a default.
    const body = {
      input: input.text,
      ...(input.sessionID ? { session_id: input.sessionID } : {}),
      provider: input.model.provider,
      model: input.model.model,
      require_model_lock: true,
    }
    return run(await this.json("/v1/runs", { method: "POST", headers: { "Idempotency-Key": input.idempotencyKey }, body: JSON.stringify(body) }), input.sessionID)
  }

  async status(runID: string): Promise<HermesRun> { return run(await this.json(`/v1/runs/${encodeURIComponent(runID)}`), "") }
  async steer(runID: string, text: string): Promise<void> { await this.json(`/v1/runs/${encodeURIComponent(runID)}/steer`, { method: "POST", body: JSON.stringify({ input: text }) }) }
  async stop(runID: string): Promise<void> { await this.json(`/v1/runs/${encodeURIComponent(runID)}/stop`, { method: "POST" }) }
  async history(sessionID: string): Promise<readonly HermesHistoryMessage[]> {
    let value: unknown

    try {
      value = await this.json(`/api/sessions/${encodeURIComponent(sessionID)}/messages?order=oldest&limit=500`)
    } catch (error) {
      // A gateway restart can discard an already-persisted Commander session.
      // Its transcript is optional; the next run recreates it under the same id.
      if (error instanceof HermesResponseError && error.status === 404) return []
      throw error
    }

    if (!object(value) || !Array.isArray(value.data)) throw new Error("Hermes returned invalid session history.")
    return value.data.flatMap((message): HermesHistoryMessage[] => {
      if (!object(message) || (message.role !== "user" && message.role !== "assistant") || typeof message.content !== "string") return []
      return [{ role: message.role, content: message.content }]
    })
  }

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
    if (!response.ok) throw new HermesResponseError(response.status)
    return response.json()
  }

  private headers(extra: HeadersInit = {}): Headers {
    const headers = new Headers(extra)
    headers.set("Authorization", `Bearer ${this.token}`)
    headers.set("Content-Type", "application/json")
    return headers
  }
}

class HermesResponseError extends Error {
  constructor(readonly status: number) {
    super(`Hermes request failed (${status}).`)
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
function modelOptions(value: unknown): readonly HermesModelOption[] {
  if (!object(value) || !Array.isArray(value.providers)) throw new Error("Hermes returned invalid model options.")
  return value.providers.flatMap((provider): HermesModelOption[] => {
    if (!object(provider) || typeof provider.slug !== "string" || typeof provider.name !== "string" || !Array.isArray(provider.models)) return []
    return provider.models.filter((model): model is string => typeof model === "string" && model.length > 0).map((model) => ({ provider: provider.slug, providerName: provider.name, model }))
  })
}
