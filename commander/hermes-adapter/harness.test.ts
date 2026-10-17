import assert from "node:assert/strict"
import test from "node:test"
import { CommanderHarness } from "./harness"
import type { CommanderHarnessState, CommanderHarnessStore, HermesGateway } from "./contract"

function fixture() {
  let state: CommanderHarnessState = { revision: 0, runs: {} }
  const starts: unknown[] = []
  const selected: unknown[] = []
  const gateway: HermesGateway = {
    capabilities: async () => ({ features: { run_submission: true } }),
    models: async () => [{ provider: "operator", providerName: "Operator", model: "configured-model" }],
    setModel: async (model) => { selected.push(model) },
    start: async (input) => { starts.push(input); return { runID: "run_1", sessionID: input.sessionID ?? "session_1", status: "started", model: input.model } },
    status: async (runID) => ({ runID, sessionID: "session_1", status: "completed" }),
    steer: async () => undefined,
    stop: async () => undefined,
    async *events() { yield { seq: 1, type: "run.completed", run_id: "run_1" } },
    history: async () => [{ role: "assistant", content: "persisted" }],
  }
  const store: CommanderHarnessStore = { read: async () => state, write: async (next) => { state = next } }
  return { harness: new CommanderHarness(gateway, store), starts, selected, state: () => state }
}

test("preserves one Hermes session and makes retries deterministic", async () => {
  const f = fixture()
  await f.harness.selectModel({ provider: "operator", model: "configured-model" })
  const first = await f.harness.start("status", "request-1")
  const second = await f.harness.start("status", "request-1")
  assert.match(first.sessionID, /^commander_/)
  assert.equal(second.sessionID, first.sessionID)
  assert.equal(f.state().sessionID, first.sessionID)
  assert.equal(f.state().model?.model, "configured-model")
  assert.deepEqual(f.starts, [
    { text: "status", sessionID: first.sessionID, model: "configured-model", idempotencyKey: (f.starts[0] as { idempotencyKey: string }).idempotencyKey },
  ])
})

test("exposes status, event replay, steer, and stop without an OpenCode worker session", async () => {
  const f = fixture()
  const started = await f.harness.start("ping")
  assert.equal((await f.harness.status(started.id)).status, "completed")
  assert.deepEqual(await Array.fromAsync(f.harness.events(started.id)), [{ seq: 1, type: "completed", runID: started.id }])
  await f.harness.steer(started.id, "be brief")
  await f.harness.stop(started.id)
  assert.deepEqual(await f.harness.history(), [{ role: "assistant", content: "persisted" }])
})

test("rejects unknown opaque run references", async () => {
  const f = fixture()
  await assert.rejects(f.harness.status(`cmd_${"0".repeat(64)}`), /not found/)
  await assert.rejects(f.harness.stop("run_1"), /invalid/)
})

test("confirms the exact Hermes provider and model before saving selection", async () => {
  const f = fixture()
  await assert.rejects(f.harness.selectModel({ provider: "operator", model: "unavailable" }), /not available from Hermes/)
  assert.equal(f.state().revision, 0)
  assert.deepEqual(f.selected, [])

  await f.harness.selectModel({ provider: "operator", model: "configured-model" })
  assert.deepEqual(f.selected, [{ provider: "operator", model: "configured-model" }])
  assert.deepEqual(f.state().model, { provider: "operator", model: "configured-model" })
})
