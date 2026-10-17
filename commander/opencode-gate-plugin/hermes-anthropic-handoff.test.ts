import assert from "node:assert/strict"
import test from "node:test"
import { startAnthropicHermesHandoff } from "./hermes-anthropic-handoff.ts"

const originalMode = process.env.DIGITALTWIN_HERMES_ANTHROPIC_HANDOFF
const originalRoot = process.env.DIGITALTWIN_REPO_ROOT

function fixture(credential: unknown) {
  const starts: Array<Readonly<{ command: readonly string[]; cwd: string; env: Readonly<Record<string, string>> }>> = []
  let kills = 0
  const context = {
    integration: {
      connection: {
        active: async () => ({ id: "con_anthropic" }),
        resolve: async () => credential,
      },
    },
    event: { subscribe: () => never() },
  }
  const spawn = (command: readonly string[], options: Readonly<{ cwd: string; env: Readonly<Record<string, string>> }>) => {
    starts.push({ command, ...options })
    return { exited: Promise.resolve(0), kill: () => { kills += 1 } }
  }
  return { context, spawn, starts, kills: () => kills }
}

test("passes only an active Anthropic API key to the project-local Hermes gateway", async () => {
  process.env.DIGITALTWIN_HERMES_ANTHROPIC_HANDOFF = "anthropic-api-key"
  process.env.DIGITALTWIN_REPO_ROOT = "/srv/digitaltwin"
  const f = fixture({ type: "key", key: "fixture-api-key" })

  const stop = await startAnthropicHermesHandoff(f.context as never, f.spawn)

  assert.deepEqual(f.starts, [{
    command: ["sh", "/srv/digitaltwin/scripts/local-hermes-gateway", "gateway"],
    cwd: "/srv/digitaltwin",
    env: {
      PATH: process.env.PATH as string,
      DIGITALTWIN_REPO_ROOT: "/srv/digitaltwin",
      DIGITALTWIN_HERMES_AUTH_HANDOFF: "anthropic-api-key",
      ANTHROPIC_API_KEY: "fixture-api-key",
    },
  }])
  await stop()
  assert.equal(f.kills(), 1)
})

test("rejects OAuth, external, and missing Anthropic credentials", async () => {
  process.env.DIGITALTWIN_HERMES_ANTHROPIC_HANDOFF = "anthropic-api-key"
  process.env.DIGITALTWIN_REPO_ROOT = "/srv/digitaltwin"

  for (const credential of [
    { type: "oauth", access: "fixture-oauth" },
    { type: "external", methodID: "fixture-external" },
    undefined,
  ]) {
    const f = fixture(credential)
    const stop = await startAnthropicHermesHandoff(f.context as never, f.spawn)
    assert.equal(f.starts.length, 0)
    await stop()
  }
})

test.after(() => {
  if (originalMode === undefined) delete process.env.DIGITALTWIN_HERMES_ANTHROPIC_HANDOFF
  else process.env.DIGITALTWIN_HERMES_ANTHROPIC_HANDOFF = originalMode
  if (originalRoot === undefined) delete process.env.DIGITALTWIN_REPO_ROOT
  else process.env.DIGITALTWIN_REPO_ROOT = originalRoot
})

async function* never(): AsyncIterable<never> {
  await new Promise<void>(() => undefined)
}
