import { randomUUID } from "node:crypto"
import { mkdir, readFile, rename, writeFile } from "node:fs/promises"
import { dirname } from "node:path"

export type FutureTaskDelivery = Readonly<{
  deliveryKey: string
  taskId: string
  text: string
  references: readonly string[]
  dueAt: string
  timezone: string
  commanderItemId: string
}>

export type FutureTaskResolution = FutureTaskDelivery | Readonly<{ deliveryKey: string; terminalFailure: string }>

/** A trusted delivery adapter may use this only for a known permanent rejection. */
export class PermanentFutureTaskDeliveryError extends Error {}

export interface FutureTaskDeliveryStore {
  load(deliveryKey: string): Promise<FutureTaskResolution | undefined>
  save(delivery: FutureTaskResolution): Promise<void>
}

/** Test-only store. Operator deployments use FileFutureTaskDeliveryStore or a transactional replacement. */
export class InMemoryFutureTaskDeliveryStore implements FutureTaskDeliveryStore {
  private readonly values = new Map<string, FutureTaskResolution>()

  async load(deliveryKey: string): Promise<FutureTaskResolution | undefined> { return this.values.get(deliveryKey) }
  async save(delivery: FutureTaskResolution): Promise<void> { this.values.set(delivery.deliveryKey, delivery) }
}

/** Durable single-process receipt store. The key is immutable and writes are atomic. */
export class FileFutureTaskDeliveryStore implements FutureTaskDeliveryStore {
  private readonly path: string
  private tail: Promise<void> = Promise.resolve()

  constructor(path: string) { this.path = path }

  async load(deliveryKey: string): Promise<FutureTaskResolution | undefined> { return (await this.read())[deliveryKey] }

  async save(delivery: FutureTaskResolution): Promise<void> {
    const next = this.tail.then(() => this.saveNow(delivery), () => this.saveNow(delivery))
    this.tail = next.then(() => undefined, () => undefined)
    return next
  }

  private async saveNow(delivery: FutureTaskResolution): Promise<void> {
    const current = await this.read()
    const next = { ...current, [delivery.deliveryKey]: delivery }
    await mkdir(dirname(this.path), { recursive: true, mode: 0o700 })
    const temporary = `${this.path}.${process.pid}.${randomUUID()}.tmp`
    await writeFile(temporary, JSON.stringify(next), { encoding: "utf8", mode: 0o600, flag: "wx" })
    await rename(temporary, this.path)
  }

  private async read(): Promise<Readonly<Record<string, FutureTaskResolution>>> {
    try {
      const value: unknown = JSON.parse(await readFile(this.path, "utf8"))
      if (!isRecord(value)) throw new Error("Invalid future-task receipt store")
      const deliveries: Record<string, FutureTaskResolution> = {}
      for (const [key, delivery] of Object.entries(value)) {
        const decoded = decode(delivery)
        if (!decoded || decoded.deliveryKey !== key) throw new Error("Invalid future-task receipt")
        deliveries[key] = decoded
      }
      return deliveries
    } catch (error: unknown) {
      if (isMissingFile(error)) return {}
      throw error
    }
  }
}

export class FutureTaskDeliveryService {
  private readonly store: FutureTaskDeliveryStore
  private readonly publish: (input: Readonly<{ deliveryKey: string; taskId: string; text: string; references: readonly string[]; dueAt: string; timezone: string }>) => Promise<string>
  private tail: Promise<void> = Promise.resolve()

  constructor(input: Readonly<{ store: FutureTaskDeliveryStore; publish: (input: Readonly<{ deliveryKey: string; taskId: string; text: string; references: readonly string[]; dueAt: string; timezone: string }>) => Promise<string> }>) { this.store = input.store; this.publish = input.publish }

  async deliver(input: Readonly<{ deliveryKey: string; taskId: string; text: string; references: readonly string[]; dueAt: string; timezone: string }>): Promise<FutureTaskResolution> {
    const result = this.tail.then(() => this.deliverNow(input), () => this.deliverNow(input))
    this.tail = result.then(() => undefined, () => undefined)
    return result
  }

  private async deliverNow(input: Readonly<{ deliveryKey: string; taskId: string; text: string; references: readonly string[]; dueAt: string; timezone: string }>): Promise<FutureTaskResolution> {
    const existing = await this.store.load(input.deliveryKey)
    if (existing) {
      if (!isTerminal(existing) && !sameDelivery(existing, input)) throw new Error("delivery_key_reused")
      return existing
    }
    let delivery: FutureTaskResolution
    try { delivery = { ...input, commanderItemId: await this.publish(input) } }
    catch (error) {
      if (!(error instanceof PermanentFutureTaskDeliveryError)) throw error
      delivery = { deliveryKey: input.deliveryKey, terminalFailure: error.message }
    }
    await this.store.save(delivery)
    return delivery
  }

  async reconcile(deliveryKey: string): Promise<FutureTaskResolution | undefined> { return this.store.load(deliveryKey) }
}

function sameDelivery(existing: FutureTaskDelivery, input: Readonly<{ deliveryKey: string; taskId: string; text: string; references: readonly string[]; dueAt: string; timezone: string }>): boolean {
  return existing.taskId === input.taskId && existing.text === input.text && existing.dueAt === input.dueAt && existing.timezone === input.timezone && JSON.stringify(existing.references) === JSON.stringify(input.references)
}

function decode(value: unknown): FutureTaskResolution | undefined {
  if (!isRecord(value)) return undefined
  if (typeof value.deliveryKey === "string" && typeof value.terminalFailure === "string") return { deliveryKey: value.deliveryKey, terminalFailure: value.terminalFailure }
  const keys = ["deliveryKey", "taskId", "text", "dueAt", "timezone", "commanderItemId"]
  if (!keys.every((key) => typeof value[key] === "string") || !Array.isArray(value.references) || !value.references.every((item) => typeof item === "string")) return undefined
  return { deliveryKey: value.deliveryKey as string, taskId: value.taskId as string, text: value.text as string, references: value.references as string[], dueAt: value.dueAt as string, timezone: value.timezone as string, commanderItemId: value.commanderItemId as string }
}

function isTerminal(value: FutureTaskResolution): value is Readonly<{ deliveryKey: string; terminalFailure: string }> { return "terminalFailure" in value }

function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value) }
function isMissingFile(error: unknown): error is NodeJS.ErrnoException { return isRecord(error) && error.code === "ENOENT" }
