import { createHash, randomUUID } from "node:crypto"
import type { CommanderEvent, CommanderHarnessState, CommanderHarnessStore, CommanderRun, HermesEvent, HermesGateway, HermesHistoryMessage, HermesModel, HermesModelOption, HermesRun } from "./contract"

export class CommanderHarness {
  constructor(
    private readonly gateway: HermesGateway,
    private readonly store: CommanderHarnessStore,
    private readonly allowedProvider?: string,
  ) {}

  capabilities(): Promise<unknown> { return this.gateway.capabilities() }
  async models(): Promise<readonly HermesModelOption[]> {
    const models = await this.gateway.models()
    return this.allowedProvider ? models.filter((model) => model.provider === this.allowedProvider) : models
  }
  state(): Promise<CommanderHarnessState> { return this.store.read() }
  async history(): Promise<readonly HermesHistoryMessage[]> {
    const sessionID = (await this.store.read()).sessionID
    return sessionID ? this.gateway.history(sessionID) : []
  }

  async selectModel(model: HermesModel): Promise<CommanderHarnessState> {
    await this.confirmModel(model)
    const current = await this.store.read()
    const next = { ...current, revision: current.revision + 1, model }
    await this.store.write(next)
    return next
  }

  async start(text: string, requestID = randomUUID(), deliveryKey?: string): Promise<CommanderRun> {
    if (!text.trim()) throw new Error("Commander prompt must not be empty.")
    if (!identifier(requestID)) throw new Error("Commander request ID is invalid.")
    const current = await this.store.read()
    const existing = current.runs[requestID]
    if (existing) return existing
    if (!current.model) throw new Error("Choose an enabled Commander model before sending.")
    await this.confirmModel(current.model)
    const sessionID = current.sessionID ?? `commander_${randomUUID()}`
    // Persist the client-selected session first. Hermes' 202 admission does not
    // echo session_id, so this makes a retry/restart use the exact same identity.
    const prepared = current.sessionID ? current : { ...current, revision: current.revision + 1, sessionID }
    if (!current.sessionID) await this.store.write(prepared)
    let started: HermesRun
    try {
      started = await this.gateway.start({ text, sessionID, model: current.model, idempotencyKey: idempotency(requestID, text) })
    } catch (error) {
      const cause = error instanceof Error ? error.message : "Hermes rejected the run."
      throw new Error(`Hermes could not use the selected Commander model. Configure compatible Hermes authentication or a shared LiteLLM route; no OpenCode fallback was used. ${cause}`)
    }
    const run: CommanderRun = { id: opaqueID(requestID), hermesRunID: started.runID, sessionID, requestID, ...(deliveryKey ? { deliveryKey } : {}) }
    await this.store.write({ ...prepared, revision: prepared.revision + 1, runs: { ...prepared.runs, [requestID]: run } })
    return run
  }

  async status(id: string): Promise<HermesRun> { const run = await this.run(id); return { ...(await this.gateway.status(run.hermesRunID)), sessionID: run.sessionID } }
  async steer(id: string, text: string): Promise<void> { if (!text.trim()) throw new Error("Commander steer text must not be empty."); await this.gateway.steer((await this.run(id)).hermesRunID, text) }
  async stop(id: string): Promise<void> { await this.gateway.stop((await this.run(id)).hermesRunID) }
  async *events(id: string, after?: number): AsyncIterable<CommanderEvent> {
    const run = await this.run(id)
    for await (const item of this.gateway.events(run.hermesRunID, after)) {
      const mapped = commanderEvent(item, run.id)
      if (mapped) yield mapped
    }
  }

  private async run(id: string): Promise<CommanderRun> {
    if (!/^cmd_[a-f0-9]{64}$/.test(id)) throw new Error("Commander run reference is invalid.")
    const found = Object.values((await this.store.read()).runs).find((run) => run.id === id)
    if (!found) throw new Error("Commander run reference was not found.")
    return found
  }

  private async confirmModel(model: HermesModel): Promise<void> {
    validModel(model, this.allowedProvider)
    const available = await this.models()
    if (!available.some((item) => item.provider === model.provider && item.model === model.model)) {
      throw new Error("Hermes does not expose the selected Commander provider and model.")
    }
  }
}

function validModel(model: HermesModel, allowedProvider?: string): void {
  if (!model.provider.trim() || !model.model.trim()) throw new Error("Hermes model provider and model are required.")
  if (allowedProvider && model.provider !== allowedProvider) throw new Error(`Commander is configured only for the ${allowedProvider} provider.`)
}
function identifier(value: string): boolean { return /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,255}$/.test(value) }
function opaqueID(value: string): string { return `cmd_${createHash("sha256").update(value, "utf8").digest("hex")}` }
function idempotency(requestID: string, text: string): string { return `commander-${createHash("sha256").update(`${requestID}\n${text}`, "utf8").digest("hex")}` }
function commanderEvent(event: HermesEvent, runID: string): CommanderEvent {
  const type = event.type.toLowerCase()
  const text = typeof event.text === "string" ? event.text : typeof event.output === "string" ? event.output : undefined
  if (type.includes("memory")) return { seq: event.seq, type: "learning", runID, learning: "memory" }
  if (type.includes("skill")) return { seq: event.seq, type: "learning", runID, learning: "skill" }
  if (type.includes("approval")) return { seq: event.seq, type: "approval", runID }
  if (type.includes("completed")) return { seq: event.seq, type: "completed", runID, ...(text ? { text } : {}) }
  if (type.includes("failed") || type.includes("error")) return { seq: event.seq, type: "failed", runID, ...(text ? { text } : {}) }
  if (text) return { seq: event.seq, type: "output", runID, text }
  return { seq: event.seq, type: "status", runID }
}
