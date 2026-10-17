export type Json = null | boolean | number | string | readonly Json[] | Readonly<{ readonly [key: string]: Json }>

export type CommanderProject = Readonly<{
  id: string
  name: string
  directory: string
}>

export type CommanderSession = Readonly<{
  id: string
  projectID: string
}>

export type CommanderMessage = Readonly<{
  id: string
  type: string
  text?: string
  metadata?: Readonly<Record<string, Json>>
  content?: readonly Readonly<{
    type: string
    text?: string
  }>[]
}>

export interface OpenCodeCommanderGateway {
  listProjects(): Promise<readonly CommanderProject[]>
  createSession(input: Readonly<{ id: string; directory: string }>): Promise<CommanderSession>
  prompt(input: Readonly<{
    sessionID: string
    messageID: string
    text: string
    metadata: Readonly<Record<string, Json>>
  }>): Promise<CommanderMessage>
  readSession(sessionID: string): Promise<CommanderSession>
  readMessages(sessionID: string): Promise<readonly CommanderMessage[]>
}

export type DelegationDecision = Readonly<{
  decisionID: string
  subject: string
  projectID: string
  sessionID: string
  createRequestID: string
  createDigest: string
  createMessageID: string
  continued: Readonly<Record<string, string>>
}>

export type PendingDelegation = Readonly<{
  decisionID: string
  subject: string
  projectID: string
  sessionID: string
  createRequestID: string
  createDigest: string
  createMessageID: string
}>

export type DelegationState = Readonly<{
  revision: number
  decisions: Readonly<Record<string, DelegationDecision>>
  requests: Readonly<Record<string, string>>
  pending: Readonly<Record<string, PendingDelegation>>
}>

export interface DelegationStore {
  read(): Promise<DelegationState>
  write(next: DelegationState): Promise<void>
  exclusive<T>(work: () => Promise<T>): Promise<T>
}
