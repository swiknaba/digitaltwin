import type { CommanderAgentDecision } from "./commander-agent-decision.ts"

export interface CommanderAgentDecisionStore {
  load(id: string): Promise<CommanderAgentDecision | undefined>
  save(decision: CommanderAgentDecision): Promise<"saved" | "conflict">
}
