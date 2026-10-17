import { createHash, randomUUID } from "node:crypto"
import type { CommanderHarnessState, CommanderHarnessStore, HermesGateway, HermesModel, HermesRun } from "./contract"

export class CommanderHarness {
  constructor(private readonly gateway: HermesGateway, private readonly store: CommanderHarnessStore) {}

  capabilities() { return this.gateway.capabilities() }
  models() { return this.gateway.models() }
  async state() { return this.store.read() }

  async selectModel(model: HermesModel): Promise<CommanderHarnessState> {
    const current = await this.store.read()
    const next = { ...current, revision: current.revision + 1, model }
    await this.store.write(next)
    return next
  }

  async start(text: string, requestID = randomUUID()): Promise<HermesRun> {
    if (!text.trim()) throw new Error("Commander prompt must not be empty.")
    const current = await this.store.read()
    const started = await this.gateway.start({ text, sessionID: current.sessionID, model: current.model?.model, idempotencyKey: idempotency(requestID, text) })
    if (current.sessionID && current.sessionID !== started.sessionID) throw new Error("Hermes changed the persistent Commander session.")
    if (!current.sessionID) await this.store.write({ ...current, revision: current.revision + 1, sessionID: started.sessionID })
    return started
  }

  status(runID: string) { return this.gateway.status(runID) }
  steer(runID: string, text: string) { return this.gateway.steer(runID, text) }
  stop(runID: string) { return this.gateway.stop(runID) }
  events(runID: string, after?: number) { return this.gateway.events(runID, after) }
}

function idempotency(requestID: string, text: string) {
  return `commander-${createHash("sha256").update(`${requestID}\n${text}`, "utf8").digest("hex")}`
}
