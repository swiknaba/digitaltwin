import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises"
import { dirname } from "node:path"
import type { DelegationDecision, DelegationState, DelegationStore, PendingDelegation } from "./contract"

const empty = (): DelegationState => ({ revision: 0, decisions: {}, requests: {}, pending: {} })
const lockTimeoutMilliseconds = 10_000
const lockRetryMilliseconds = 25

export class FileDelegationStore implements DelegationStore {
  constructor(private readonly path: string) {}

  async read(): Promise<DelegationState> {
    try {
      return decodeState(JSON.parse(await readFile(this.path, "utf8")))
    } catch (error) {
      if (isNotFound(error)) return empty()
      throw error
    }
  }

  async write(next: DelegationState): Promise<void> {
    const state = decodeState(next)
    await mkdir(dirname(this.path), { recursive: true, mode: 0o700 })
    const temporary = `${this.path}.${process.pid}.tmp`
    await writeFile(temporary, `${JSON.stringify(state)}\n`, { encoding: "utf8", mode: 0o600 })
    await rename(temporary, this.path)
  }

  async exclusive<T>(work: () => Promise<T>): Promise<T> {
    const release = await this.acquireLock()
    try {
      return await work()
    } finally {
      await release()
    }
  }

  private async acquireLock(): Promise<() => Promise<void>> {
    const lock = `${this.path}.lock`
    await mkdir(dirname(lock), { recursive: true, mode: 0o700 })
    const deadline = Date.now() + lockTimeoutMilliseconds
    for (;;) {
      try {
        await mkdir(lock, { mode: 0o700 })
        await writeFile(`${lock}/owner`, `${process.pid}\n`, { encoding: "utf8", mode: 0o600 })
        return async () => { await rm(lock, { recursive: true, force: true }) }
      } catch (error) {
        if (!isAlreadyExists(error)) throw error
        if (await stale(lock)) {
          await rm(lock, { recursive: true, force: true })
          continue
        }
        if (Date.now() >= deadline) throw new Error("Commander delegation state is busy; retry the request.")
        await pause(lockRetryMilliseconds)
      }
    }
  }
}

async function stale(lock: string): Promise<boolean> {
  try {
    const owner = (await readFile(`${lock}/owner`, "utf8")).trim()
    if (/^[1-9][0-9]*$/.test(owner)) return !running(Number(owner))
  } catch (error) {
    if (!isNotFound(error)) throw error
  }
  return false
}

function running(pid: number): boolean {
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    if (object(error) && error.code === "ESRCH") return false
    if (object(error) && error.code === "EPERM") return true
    throw error
  }
}

function pause(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds))
}

function decodeState(value: unknown): DelegationState {
  if (!object(value) || !Number.isSafeInteger(value.revision) || value.revision < 0 || !object(value.decisions) || !object(value.requests) || (value.pending !== undefined && !object(value.pending))) {
    throw new Error("Commander delegation state is invalid.")
  }
  const decisions: Record<string, DelegationDecision> = {}
  for (const [key, item] of Object.entries(value.decisions)) decisions[key] = decodeDecision(key, item)
  const requests: Record<string, string> = {}
  for (const [key, decisionID] of Object.entries(value.requests)) {
    if (!requestKey(key) || typeof decisionID !== "string" || !decisionKey(decisionID)) throw new Error("Commander delegation request state is invalid.")
    requests[key] = decisionID
  }
  const pending: Record<string, PendingDelegation> = {}
  for (const [key, item] of Object.entries(value.pending ?? {})) {
    if (!requestKey(key)) throw new Error("Commander pending delegation state is invalid.")
    pending[key] = decodePending(item)
  }
  return { revision: value.revision, decisions, requests, pending }
}

function decodeDecision(key: string, value: unknown): DelegationDecision {
  if (!decisionKey(key) || !object(value) || typeof value.decisionID !== "string" || value.decisionID !== key || typeof value.subject !== "string" || typeof value.projectID !== "string" || typeof value.sessionID !== "string" || typeof value.createRequestID !== "string" || typeof value.createDigest !== "string" || typeof value.createMessageID !== "string" || !object(value.continued)) {
    throw new Error("Commander delegation decision state is invalid.")
  }
  if (!identifier(value.subject) || !identifier(value.projectID) || !identifier(value.sessionID) || !requestID(value.createRequestID) || !digest(value.createDigest) || !messageID(value.createMessageID)) {
    throw new Error("Commander delegation decision state is invalid.")
  }
  const continued: Record<string, string> = {}
  for (const [requestIDValue, requestDigest] of Object.entries(value.continued)) {
    if (!requestID(requestIDValue) || typeof requestDigest !== "string" || !digest(requestDigest)) throw new Error("Commander continuation state is invalid.")
    continued[requestIDValue] = requestDigest
  }
  return {
    decisionID: value.decisionID,
    subject: value.subject,
    projectID: value.projectID,
    sessionID: value.sessionID,
    createRequestID: value.createRequestID,
    createDigest: value.createDigest,
    createMessageID: value.createMessageID,
    continued,
  }
}

function decodePending(value: unknown): PendingDelegation {
  if (!object(value) || typeof value.decisionID !== "string" || typeof value.subject !== "string" || typeof value.projectID !== "string" || typeof value.sessionID !== "string" || typeof value.createRequestID !== "string" || typeof value.createDigest !== "string" || typeof value.createMessageID !== "string") {
    throw new Error("Commander pending delegation state is invalid.")
  }
  if (!decisionKey(value.decisionID) || !identifier(value.subject) || !identifier(value.projectID) || !identifier(value.sessionID) || !requestID(value.createRequestID) || !digest(value.createDigest) || !messageID(value.createMessageID)) {
    throw new Error("Commander pending delegation state is invalid.")
  }
  return {
    decisionID: value.decisionID,
    subject: value.subject,
    projectID: value.projectID,
    sessionID: value.sessionID,
    createRequestID: value.createRequestID,
    createDigest: value.createDigest,
    createMessageID: value.createMessageID,
  }
}

function object(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value) }
function isNotFound(error: unknown): boolean { return object(error) && error.code === "ENOENT" }
function isAlreadyExists(error: unknown): boolean { return object(error) && error.code === "EEXIST" }
function identifier(value: string): boolean { return /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,255}$/.test(value) }
function requestID(value: string): boolean { return /^[A-Za-z0-9][A-Za-z0-9_-]{0,255}$/.test(value) }
function digest(value: string): boolean { return /^[a-f0-9]{64}$/.test(value) }
function messageID(value: string): boolean { return /^msg_hermes_commander_[a-f0-9]{64}$/.test(value) }
function decisionKey(value: string): boolean { return /^hermes-project-session-[a-f0-9]{64}$/.test(value) }
function requestKey(value: string): boolean { return /^[a-f0-9]{64}$/.test(value) }
