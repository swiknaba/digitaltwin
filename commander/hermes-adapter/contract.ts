export type HermesModel = Readonly<{ provider: string; model: string }>

export type CommanderHarnessState = Readonly<{
  revision: number
  sessionID?: string
  model?: HermesModel
}>

export type HermesRun = Readonly<{
  runID: string
  sessionID: string
  status: string
  model?: string
}>

export type HermesEvent = Readonly<{
  seq: number
  type: string
  run_id: string
  [key: string]: unknown
}>

export interface HermesGateway {
  capabilities(): Promise<unknown>
  models(): Promise<unknown>
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
