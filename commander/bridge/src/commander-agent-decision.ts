import type { OpenCodeMessageProvenance } from "./contract.ts"

/** Immutable record created when Commander starts an OpenCode agent session. */
export type CommanderAgentDecision = Readonly<{
  id: string
  provenance: OpenCodeMessageProvenance
}>

export function validCommanderAgentDecision(value: CommanderAgentDecision): boolean {
  return /^[a-z0-9][a-z0-9_-]{0,127}$/i.test(value.id)
}
