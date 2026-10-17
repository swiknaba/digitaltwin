export type HermesModel = Readonly<{ provider: string; model: string }>

export type HermesRun = Readonly<{ runID: string; sessionID: string; status: string; model?: string }>

export type CommanderRun = Readonly<{
  id: string
  hermesRunID: string
  sessionID: string
  requestID: string
  deliveryKey?: string
}>

export type CommanderHarnessState = Readonly<{
  revision: number
  sessionID?: string
  model?: HermesModel
  runs: Readonly<Record<string, CommanderRun>>
}>

export type HermesEvent = Readonly<{ seq: number; type: string; run_id: string; [key: string]: unknown }>

export type CommanderEvent = Readonly<{
  seq: number
  type: "output" | "completed" | "failed" | "approval" | "learning" | "status"
  runID: string
  text?: string
  learning?: "memory" | "skill"
}>

export interface HermesGateway {
  capabilities(): Promise<unknown>
  models(): Promise<unknown>
  setModel(model: HermesModel): Promise<void>
  start(input: Readonly<{ text: string; sessionID?: string; model?: string; idempotencyKey: string }>): Promise<HermesRun>
  status(runID: string): Promise<HermesRun>
  steer(runID: string, text: string): Promise<void>
  stop(runID: string): Promise<void>
  events(runID: string, after?: number): AsyncIterable<HermesEvent>
}

export interface CommanderHarnessStore {
  read(): Promise<CommanderHarnessState>
  write(state: CommanderHarnessState): Promise<void>
}
