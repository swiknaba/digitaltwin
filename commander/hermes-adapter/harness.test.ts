import assert from "node:assert/strict"
import test from "node:test"
import { CommanderHarness } from "./harness"
import type { CommanderHarnessState, CommanderHarnessStore, HermesGateway } from "./contract"

function fixture() {
  let state: CommanderHarnessState = { revision: 0, runs: {} }
  const starts: unknown[] = []
  const gateway: HermesGateway = {
    capabilities: async () => ({ features: { run_submission: true } }),
    models: async () => [{ provider: "operator", providerName: "Operator", model: "configured-model" }],
    start: async (input) => { starts.push(input); return { runID: "run_1", sessionID: input.sessionID ?? "session_1", status: "started", model: input.model } },
    status: async (runID) => ({ runID, sessionID: "session_1", status: "completed" }),
    steer: async () => undefined,
    stop: async () => undefined,
    async *events() { yield { seq: 1, type: "run.completed", run_id: "run_1" } },
    history: async () => [{ role: "assistant", content: "persisted" }],
  }
  const store: CommanderHarnessStore = { read: async () => state, write: async (next) => { state = next } }
  return { harness: new CommanderHarness(gateway, store), starts, state: () => state }
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
    { text: "status", sessionID: first.sessionID, model: { provider: "operator", model: "configured-model" }, idempotencyKey: (f.starts[0] as { idempotencyKey: string }).idempotencyKey },
  ])
})

test("requires a Commander model before a Hermes run", async () => {
  const f = fixture()
  await assert.rejects(f.harness.start("ping"), /Choose an enabled Commander model/)
  await f.harness.selectModel({ provider: "operator", model: "configured-model" })
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

test("persists an exact Commander provider and model without requiring a Hermes global model inventory", async () => {
  const f = fixture()
  await f.harness.selectModel({ provider: "openai", model: "enabled-in-opencode" })
  assert.deepEqual(f.state().model, { provider: "openai", model: "enabled-in-opencode" })
})
