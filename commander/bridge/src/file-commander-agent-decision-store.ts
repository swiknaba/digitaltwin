import { createHash } from "node:crypto"
import { mkdir, readFile, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { decodeOpenCodeMessageProvenance } from "./contract.ts"
import type { CommanderAgentDecision } from "./commander-agent-decision.ts"
import type { CommanderAgentDecisionStore } from "./commander-agent-decision-store.ts"

/** JSON persistence contains only immutable identifiers, never executable values. */
export class FileCommanderAgentDecisionStore implements CommanderAgentDecisionStore {
  private readonly directory: string

  constructor(input: Readonly<{ directory: string }>) {
    this.directory = input.directory
  }

  async load(id: string): Promise<CommanderAgentDecision | undefined> {
    try {
      return decodeDecision(JSON.parse(await readFile(this.path(id), "utf8")))
    } catch {
      return undefined
    }
  }

  async save(decision: CommanderAgentDecision): Promise<"saved" | "conflict"> {
    await mkdir(this.directory, { recursive: true, mode: 0o700 })
    const existing = await this.load(decision.id)
    if (existing) return sameDecision(existing, decision) ? "saved" : "conflict"
    const destination = this.path(decision.id)
    try {
      await writeFile(destination, JSON.stringify(decision), { encoding: "utf8", mode: 0o600, flag: "wx" })
      return "saved"
    } catch {
      const raced = await this.load(decision.id)
      return raced && sameDecision(raced, decision) ? "saved" : "conflict"
    }
  }

  private path(id: string): string {
    return join(this.directory, `${createHash("sha256").update(id, "utf8").digest("hex")}.json`)
  }
}

function decodeDecision(value: unknown): CommanderAgentDecision | undefined {
  if (!isRecord(value) || typeof value.id !== "string") return undefined
  const provenance = decodeOpenCodeMessageProvenance(value.provenance)
  if (!provenance || !/^[a-z0-9][a-z0-9_-]{0,127}$/i.test(value.id)) return undefined
  return { id: value.id, provenance }
}

function sameDecision(left: CommanderAgentDecision, right: CommanderAgentDecision): boolean {
  return JSON.stringify(left) === JSON.stringify(right)
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}
