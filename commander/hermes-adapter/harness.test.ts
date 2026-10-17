import assert from "node:assert/strict"
import test from "node:test"
import { CommanderHarness } from "./harness"
import type { CommanderHarnessState, CommanderHarnessStore, HermesGateway } from "./contract"

function fixture() {
  let state: CommanderHarnessState = { revision: 0 }
  const starts: unknown[] = []
  const gateway: HermesGateway = {
    capabilities: async () => ({ features: { run_submission: true } }),
    models: async () => ({ providers: [] }),
    start: async (input) => { starts.push(input); return { runID: "run_1", sessionID: input.sessionID ?? "session_1", status: "started", model: input.model } },
    status: async (runID) => ({ runID, sessionID: "session_1", status: "completed" }),
    steer: async () => undefined,
    stop: async () => undefined,
    async *events() { yield { seq: 1, type: "run.completed", run_id: "run_1" } },
  }
  const store: CommanderHarnessStore = { read: async () => state, write: async (next) => { state = next } }
  return { harness: new CommanderHarness(gateway, store), starts, state: () => state }
}

test("preserves one Hermes session and makes retries deterministic", async () => {
  const f = fixture()
  await f.harness.selectModel({ provider: "operator", model: "configured-model" })
  const first = await f.harness.start("status", "request-1")
  const second = await f.harness.start("status", "request-1")
  assert.equal(first.sessionID, "session_1")
  assert.equal(second.sessionID, "session_1")
  assert.equal(f.state().sessionID, "session_1")
  assert.equal(f.state().model?.model, "configured-model")
  assert.deepEqual(f.starts, [
    { text: "status", sessionID: undefined, model: "configured-model", idempotencyKey: (f.starts[0] as { idempotencyKey: string }).idempotencyKey },
    { text: "status", sessionID: "session_1", model: "configured-model", idempotencyKey: (f.starts[0] as { idempotencyKey: string }).idempotencyKey },
  ])
})

test("exposes status, event replay, steer, and stop without an OpenCode worker session", async () => {
  const f = fixture()
  const started = await f.harness.start("ping")
  assert.equal((await f.harness.status(started.runID)).status, "completed")
  assert.deepEqual(await Array.fromAsync(f.harness.events(started.runID)), [{ seq: 1, type: "run.completed", run_id: "run_1" }])
  await f.harness.steer(started.runID, "be brief")
  await f.harness.stop(started.runID)
})
