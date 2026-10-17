import { resolve } from "node:path"
import type { Plugin } from "@opencode/plugin"

const integrationID = "anthropic"
const handoffMode = "anthropic-api-key"

type HandoffChild = Readonly<{
  exited: Promise<number>
  kill(signal?: number | NodeJS.Signals): void
}>

type HandoffSpawner = (command: readonly string[], options: Readonly<{ cwd: string; env: Readonly<Record<string, string>> }>) => HandoffChild

type HandoffContext = Pick<Plugin.Context, "integration" | "event">

export async function startAnthropicHermesHandoff(
  context: HandoffContext,
  spawn: HandoffSpawner = spawnGateway,
): Promise<() => Promise<void>> {
  if (process.env.DIGITALTWIN_HERMES_ANTHROPIC_HANDOFF !== handoffMode) return async () => undefined

  const repositoryRoot = process.env.DIGITALTWIN_REPO_ROOT
  if (!repositoryRoot) return async () => undefined

  const root = resolve(repositoryRoot)
  const supervisor = new HandoffSupervisor(context, root, spawn, new HandoffStatus(resolve(root, "local/runtime/commander-hermes-handoff.json")))
  await supervisor.refresh()

  const controller = new AbortController()
  void observeCredentials(context, controller.signal, supervisor)
  return async () => {
    controller.abort()
    await supervisor.stop()
  }
}

class HandoffSupervisor {
  private child: HandoffChild | undefined
  private queue: Promise<void> = Promise.resolve()
  private closed = false

  constructor(
    private readonly context: Pick<Plugin.Context, "integration">,
    private readonly repositoryRoot: string,
    private readonly spawn: HandoffSpawner,
    private readonly status: HandoffStatus,
  ) {}

  async refresh(): Promise<void> {
    this.queue = this.queue.then(async () => {
      if (this.closed) return
      this.status.write("checking")
      await this.stopChild()
      const credential = await this.activeKey()
      if (!credential) {
        this.status.write("unavailable", "no-active-anthropic-api-key")
        return
      }
      if (this.closed) return
      this.child = this.spawn(
        ["sh", resolve(this.repositoryRoot, "scripts/local-hermes-gateway"), "gateway"],
        {
          cwd: this.repositoryRoot,
          env: childEnvironment(this.repositoryRoot, credential),
        },
      )
      this.status.write("started")
      void this.child.exited.then(() => undefined, () => undefined)
    })
    await this.queue
  }

  async stop(): Promise<void> {
    this.closed = true
    await this.queue
    await this.stopChild()
    this.status.write("stopped")
  }

  private async activeKey(): Promise<string | undefined> {
    try {
      const connection = await this.context.integration.connection.active(integrationID)
      if (!connection) return
      const credential = await this.context.integration.connection.resolve(connection)
      if (!credential || credential.type !== "key") return
      return credential.key.trim() || undefined
    } catch {
      return
    }
  }

  private async stopChild(): Promise<void> {
    const child = this.child
    this.child = undefined
    if (!child) return
    try {
      child.kill("SIGTERM")
    } catch {
      return
    }
    await Promise.race([child.exited.then(() => undefined, () => undefined), delay(2_000)])
  }
}

class HandoffStatus {
  constructor(private readonly path: string) {}

  write(state: "checking" | "started" | "stopped" | "unavailable", reason?: "no-active-anthropic-api-key"): void {
    void Bun.write(this.path, JSON.stringify({ state, ...(reason ? { reason } : {}) })).catch(() => undefined)
  }
}

async function observeCredentials(context: HandoffContext, signal: AbortSignal, supervisor: HandoffSupervisor): Promise<void> {
  try {
    for await (const event of context.event.subscribe({ signal })) {
      if (event.type === "credential.updated" || (event.type === "credential.switched" && event.data.integrationID === integrationID)) {
        await supervisor.refresh()
      }
    }
  } catch {
    // The next OpenCode plugin setup retries the handoff. A failed event stream must not re-enable a fallback.
  }
}

function childEnvironment(repositoryRoot: string, credential: string): Readonly<Record<string, string>> {
  const path = process.env.PATH
  if (!path) throw new Error("A PATH is required to launch the local Hermes gateway.")
  return {
    PATH: path,
    DIGITALTWIN_REPO_ROOT: repositoryRoot,
    DIGITALTWIN_HERMES_AUTH_HANDOFF: handoffMode,
    ANTHROPIC_API_KEY: credential,
  }
}

function spawnGateway(command: readonly string[], options: Readonly<{ cwd: string; env: Readonly<Record<string, string>> }>): HandoffChild {
  return Bun.spawn(command, { cwd: options.cwd, env: options.env, stdout: "ignore", stderr: "ignore" })
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds))
}
