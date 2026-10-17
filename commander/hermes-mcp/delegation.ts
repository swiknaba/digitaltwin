import { createHash } from "node:crypto"
import type { CommanderMessage, CommanderWorkerModel, DelegationDecision, DelegationState, DelegationStore, Json, OpenCodeCommanderGateway, PendingDelegation } from "./contract"

export class CommanderDelegation {
  private readonly locks = new Map<string, Promise<void>>()

  constructor(
    private readonly gateway: OpenCodeCommanderGateway,
    private readonly store: DelegationStore,
    private readonly provenanceSubject: string,
  ) {
    if (!identifier(provenanceSubject)) throw new Error("Commander provenance subject is invalid.")
  }

  async listProjects(): Promise<readonly Readonly<{ id: string; name: string; directory: string }>[]> {
    return this.gateway.listProjects()
  }

  async create(input: Readonly<{ projectID: string; requestID: string; text: string; workerModel: CommanderWorkerModel }>): Promise<Readonly<Record<string, Json>>> {
    validCreate(input)
    const requestKey = hash([this.provenanceSubject, input.projectID, input.requestID].join("\n"))
    return this.exclusive(requestKey, () => this.store.exclusive(async () => {
      const digest = createDigest(input.text, input.workerModel)
      const current = await this.store.read()
      const priorID = current.requests[requestKey]
      if (priorID) {
        const prior = current.decisions[priorID]
        if (!prior || prior.projectID !== input.projectID || !matchesCreateDigest(prior.createDigest, input.text, input.workerModel)) {
          throw new Error("Commander project session request conflicts with its original body.")
        }
        await this.admitCreate(prior, input.text)
        return createResult(prior)
      }
      const pending = current.pending[requestKey]
      if (pending) {
        if (!samePending(pending, this.provenanceSubject, input.projectID, input.requestID, digest)) {
          throw new Error("Commander project session request conflicts with its original body.")
        }
        const recovered = await this.completePending(requestKey, pending)
        await this.admitCreate(recovered, input.text)
        return createResult(recovered)
      }
      const project = (await this.gateway.listProjects()).find((item) => item.id === input.projectID)
      if (!project) throw new Error("Commander project was not found.")
      await this.assertEnabledWorkerModel(project.directory, input.workerModel)
      const intent: PendingDelegation = {
        decisionID: `hermes-project-session-${hash([this.provenanceSubject, project.id, input.requestID].join("\n"))}`,
        subject: this.provenanceSubject,
        projectID: project.id,
        sessionID: `ses_hermes_commander_${hash([this.provenanceSubject, project.id, input.requestID].join("\n"))}`,
        createRequestID: input.requestID,
        createDigest: digest,
        createMessageID: messageID(project.id, `ses_hermes_commander_${hash([this.provenanceSubject, project.id, input.requestID].join("\n"))}`, input.requestID),
        workerModel: input.workerModel,
      }
      await this.persistPending(current, requestKey, intent)
      const decision = await this.completePending(requestKey, intent, project.directory)
      await this.admitCreate(decision, input.text)
      return createResult(decision)
    }))
  }

  async read(input: Readonly<{ decisionID?: string; sessionID?: string }>): Promise<Readonly<Record<string, Json>>> {
    const decision = await this.resolve(input)
    await this.gateway.waitSession(decision.sessionID)
    const [session, messages] = await Promise.all([this.gateway.readSession(decision.sessionID), this.gateway.readMessages(decision.sessionID)])
    if (session.id !== decision.sessionID || session.projectID !== decision.projectID) throw new Error("Commander target session provenance no longer matches.")
    return {
      decision_id: decision.decisionID,
      session_id: session.id,
      project_id: session.projectID,
      provenance: provenance(decision),
      latest_result: latestAssistant(messages),
    }
  }

  async continue(input: Readonly<{ decisionID?: string; sessionID?: string; requestID: string; text: string; workerModel?: CommanderWorkerModel }>): Promise<Readonly<Record<string, Json>>> {
    if (!requestID(input.requestID) || !input.text.trim()) throw new Error("Commander continuation request is invalid.")
    const decision = await this.resolve(input)
    return this.exclusive(decision.decisionID, () => this.store.exclusive(async () => {
      const current = await this.store.read()
      const persisted = current.decisions[decision.decisionID]
      if (!persisted || persisted.subject !== this.provenanceSubject) throw new Error("Commander decision was not found.")
      validWorkerModel(input.workerModel)
      const digest = createDigest(input.text, input.workerModel)
      const existing = persisted.continued[input.requestID]
      if (existing && existing !== digest) throw new Error("Commander continuation conflicts with its original body.")
      const message = messageID(persisted.projectID, persisted.sessionID, input.requestID)
      const metadata = continuationMetadata(persisted, input.requestID, digest)
      if (input.workerModel !== undefined) {
        const project = (await this.gateway.listProjects()).find((item) => item.id === persisted.projectID)
        if (!project) throw new Error("Commander project was not found.")
        await this.assertEnabledWorkerModel(project.directory, input.workerModel)
        await this.gateway.selectSessionModel({ sessionID: persisted.sessionID, model: input.workerModel })
      }
      await this.admit(persisted.sessionID, message, input.text, metadata)
      if (!existing) {
        const next: DelegationDecision = { ...persisted, continued: { ...persisted.continued, [input.requestID]: digest } }
        await this.store.write({ ...current, revision: current.revision + 1, decisions: { ...current.decisions, [next.decisionID]: next } })
      }
      return {
        decision_id: persisted.decisionID,
        session_id: persisted.sessionID,
        project_id: persisted.projectID,
        request_id: input.requestID,
        provenance: provenance(persisted),
        ...(input.workerModel === undefined ? {} : { worker_model: workerModelJson(input.workerModel) }),
      }
    }))
  }

  private async resolve(input: Readonly<{ decisionID?: string; sessionID?: string }>): Promise<DelegationDecision> {
    if ((input.decisionID === undefined && input.sessionID === undefined) || (input.decisionID !== undefined && input.sessionID !== undefined)) {
      throw new Error("Use exactly one Commander decision_id or session_id from a previous create result.")
    }
    const current = await this.store.read()
    const decision = input.decisionID === undefined
      ? Object.values(current.decisions).find((item) => item.sessionID === input.sessionID && item.subject === this.provenanceSubject)
      : current.decisions[input.decisionID]
    if (!decision || decision.subject !== this.provenanceSubject) throw new Error("Commander decision was not found.")
    return decision
  }

  private async persistPending(current: DelegationState, requestKey: string, pending: PendingDelegation): Promise<void> {
    await this.store.write({
      revision: current.revision + 1,
      decisions: current.decisions,
      requests: current.requests,
      pending: { ...current.pending, [requestKey]: pending },
    })
  }

  private async completePending(requestKey: string, pending: PendingDelegation, knownDirectory?: string): Promise<DelegationDecision> {
    const project = knownDirectory === undefined
      ? (await this.gateway.listProjects()).find((item) => item.id === pending.projectID)
      : { id: pending.projectID, directory: knownDirectory }
    if (!project) throw new Error("Commander project was not found.")
    await this.assertEnabledWorkerModel(project.directory, pending.workerModel)
    const session = await this.gateway.createSession({ id: pending.sessionID, directory: project.directory, model: pending.workerModel })
    if (session.id !== pending.sessionID || session.projectID !== pending.projectID) throw new Error("OpenCode created a session for a different project.")
    const decision = decisionFrom(pending)
    const current = await this.store.read()
    const existingID = current.requests[requestKey]
    if (existingID) {
      const existing = current.decisions[existingID]
      if (!existing || existing.decisionID !== decision.decisionID) throw new Error("Commander project session request conflicts with its original body.")
      return existing
    }
    const persistedPending = current.pending[requestKey]
    if (!persistedPending || !samePending(persistedPending, pending.subject, pending.projectID, pending.createRequestID, pending.createDigest)) {
      throw new Error("Commander project session recovery was interrupted.")
    }
    const { [requestKey]: removed, ...remaining } = current.pending
    void removed
    await this.store.write({
      revision: current.revision + 1,
      decisions: { ...current.decisions, [decision.decisionID]: decision },
      requests: { ...current.requests, [requestKey]: decision.decisionID },
      pending: remaining,
    })
    return decision
  }

  private async admitCreate(decision: DelegationDecision, text: string): Promise<void> {
    await this.admit(decision.sessionID, decision.createMessageID, text, createMetadata(decision))
  }

  private async admit(sessionID: string, messageIDValue: string, text: string, metadata: Readonly<Record<string, Json>>): Promise<void> {
    const response = await this.gateway.prompt({ sessionID, messageID: messageIDValue, text: `Commander-directed work:\n\n${text}`, metadata })
    if (!admitted(response, sessionID, messageIDValue, `Commander-directed work:\n\n${text}`, metadata)) {
      throw new Error("Commander project session admission conflicts with the existing message.")
    }
  }

  private async assertEnabledWorkerModel(directory: string, model: CommanderWorkerModel): Promise<void> {
    const candidate = (await this.gateway.listAvailableModels(directory)).find(
      (item) => item.model.providerID === model.providerID && item.model.modelID === model.modelID,
    )
    if (!candidate || (model.variant !== undefined && !candidate.variants.includes(model.variant))) {
      throw new Error("Commander worker model is not an enabled OpenCode model for this project.")
    }
  }

  private async exclusive<T>(key: string, work: () => Promise<T>): Promise<T> {
    const previous = this.locks.get(key) ?? Promise.resolve()
    let release = () => undefined
    const current = new Promise<void>((resolve) => { release = resolve })
    const queued = previous.then(() => current)
    this.locks.set(key, queued)
    await previous
    try {
      return await work()
    } finally {
      release()
      if (this.locks.get(key) === queued) this.locks.delete(key)
    }
  }
}

function validCreate(input: Readonly<{ projectID: string; requestID: string; text: string; workerModel: CommanderWorkerModel }>): void {
  if (!identifier(input.projectID) || !requestID(input.requestID) || !input.text.trim()) throw new Error("Commander project session request is invalid.")
  if (!input.workerModel) throw new Error("Commander worker model is required for a new project session.")
  validWorkerModel(input.workerModel)
}

function createResult(decision: DelegationDecision): Readonly<Record<string, Json>> {
  return {
    decision_id: decision.decisionID,
    session_id: decision.sessionID,
    project_id: decision.projectID,
    message_id: decision.createMessageID,
    request_id: decision.createRequestID,
    provenance: provenance(decision),
    worker_model: workerModelJson(decision.workerModel),
  }
}

function provenance(decision: DelegationDecision): Readonly<Record<string, Json>> {
  return { source: "hermes-mcp", subject: decision.subject, project_id: decision.projectID, create_request_id: decision.createRequestID }
}

function createMetadata(decision: DelegationDecision): Readonly<Record<string, Json>> {
  return {
    fromCommander: true,
    commanderSource: "hermes-mcp",
    commanderProvenanceSubject: decision.subject,
    commanderDecisionID: decision.decisionID,
    commanderProjectID: decision.projectID,
    commanderRequestID: decision.createRequestID,
  }
}

function continuationMetadata(decision: DelegationDecision, request: string, digest: string): Readonly<Record<string, Json>> {
  return {
    fromCommander: true,
    commanderSource: "hermes-mcp",
    commanderProvenanceSubject: decision.subject,
    commanderDecisionID: decision.decisionID,
    commanderProjectID: decision.projectID,
    commanderRequestID: request,
    commanderRequestDigest: digest,
  }
}

function admitted(message: CommanderMessage, sessionID: string, id: string, text: string, metadata: Readonly<Record<string, Json>>): boolean {
  return message.id === id && message.type === "user" && (message.sessionID === undefined || message.sessionID === sessionID) && message.text === text && Object.entries(metadata).every(([key, value]) => message.metadata?.[key] === value)
}

function latestAssistant(messages: readonly CommanderMessage[]): Json {
  const message = messages.find((item) => item.type === "assistant")
  return message ? messageToJson(message) : null
}

function messageToJson(value: CommanderMessage): Json {
  const assistantText = value.content?.filter((part) => part.type === "text" && part.text !== undefined).map((part) => part.text).join("")
  return {
    id: value.id,
    type: value.type,
    ...(value.text === undefined && assistantText === undefined ? {} : { text: value.text ?? assistantText }),
    ...(value.model === undefined ? {} : { model: value.model }),
    ...(value.finish === undefined ? {} : { finish: value.finish }),
    ...(value.error === undefined ? {} : { error: value.error }),
  }
}

function decisionFrom(pending: PendingDelegation): DelegationDecision {
  return {
    decisionID: pending.decisionID,
    subject: pending.subject,
    projectID: pending.projectID,
    sessionID: pending.sessionID,
    createRequestID: pending.createRequestID,
    createDigest: pending.createDigest,
    createMessageID: pending.createMessageID,
    workerModel: pending.workerModel,
    continued: {},
  }
}

function samePending(pending: PendingDelegation, subject: string, projectID: string, createRequestID: string, createDigest: string): boolean {
  return pending.subject === subject && pending.projectID === projectID && pending.createRequestID === createRequestID && pending.createDigest === createDigest
}

function messageID(projectID: string, sessionID: string, requestIDValue: string): string {
  return `msg_hermes_commander_${hash([projectID, sessionID, requestIDValue].join("\n"))}`
}

function hash(value: string): string { return createHash("sha256").update(value, "utf8").digest("hex") }
function identifier(value: string): boolean { return /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,255}$/.test(value) }
function requestID(value: string): boolean { return /^[A-Za-z0-9][A-Za-z0-9_-]{0,255}$/.test(value) }
function modelID(value: string): boolean { return /^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$/.test(value) }
function validWorkerModel(value: CommanderWorkerModel | undefined): void {
  if (value === undefined) return
  if (!identifier(value.providerID) || !modelID(value.modelID) || (value.variant !== undefined && !identifier(value.variant))) {
    throw new Error("Commander worker model is invalid.")
  }
}
function createDigest(text: string, workerModel: CommanderWorkerModel | undefined): string {
  return hash(JSON.stringify({ text, ...(workerModel === undefined ? {} : { workerModel }) }))
}
function matchesCreateDigest(value: string, text: string, workerModel: CommanderWorkerModel): boolean {
  return value === createDigest(text, workerModel)
}
function workerModelJson(value: CommanderWorkerModel): Json {
  return {
    provider_id: value.providerID,
    model_id: value.modelID,
    ...(value.variant === undefined ? {} : { variant: value.variant }),
  }
}
