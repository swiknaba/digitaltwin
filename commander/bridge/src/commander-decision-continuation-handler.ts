import { validCommanderAgentDecision, type CommanderAgentDecision } from "./commander-agent-decision.ts"
import type { CommanderAgentDecisionStore } from "./commander-agent-decision-store.ts"
import { OpenCodeSessionContinuation, type ContinuationResult } from "./opencode-continuation.ts"

export type DecisionContinuationResult = ContinuationResult | Readonly<{ ok: false; reason: "decision_missing" | "decision_conflict" }>

/**
 * The actual Commander decision caller: persist exact provenance at agent start,
 * then resume only that recorded OpenCode session on a later decision.
 */
export class CommanderDecisionContinuationHandler {
  private readonly input: Readonly<{ decisions: CommanderAgentDecisionStore; continuation: OpenCodeSessionContinuation }>

  constructor(input: Readonly<{ decisions: CommanderAgentDecisionStore; continuation: OpenCodeSessionContinuation }>) {
    this.input = input
  }

  async recordAgentSession(decision: CommanderAgentDecision): Promise<"recorded" | "conflict"> {
    if (!validCommanderAgentDecision(decision)) return "conflict"
    return await this.input.decisions.save(decision) === "saved" ? "recorded" : "conflict"
  }

  async continueDecision(input: Readonly<{ decisionId: string; requestId: string; text: string }>): Promise<DecisionContinuationResult> {
    const decision = await this.input.decisions.load(input.decisionId)
    if (!decision) return { ok: false, reason: "decision_missing" }
    return await this.input.continuation.continue({ provenance: decision.provenance, requestId: input.requestId, text: input.text })
  }
}
