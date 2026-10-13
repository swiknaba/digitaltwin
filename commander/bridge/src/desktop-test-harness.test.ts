import assert from "node:assert/strict"
import test from "node:test"
import { createEphemeralDesktopHarness } from "./desktop-test-harness.ts"

test("ephemeral desktop harness drives panel actions and reconnects streamed output", async () => {
  const harness = await createEphemeralDesktopHarness()
  try {
    assert.equal((await harness.panel.open()).status, "active")
    assert.equal((await harness.panel.prompt("hello")).status, "active")
    assert.equal((await harness.panel.reconnect(0)).status, "active")
    await harness.publish("working")
    assert.equal((await harness.panel.reconnect(0)).events.at(-1)?.text, "working")
    assert.equal((await harness.panel.steer("short")).status, "active")
    assert.equal((await harness.panel.cancel()).status, "active")
    assert.deepEqual(harness.runtime.prompts, ["hello"])
    assert.deepEqual(harness.runtime.steers, ["short"])
    assert.equal(harness.runtime.cancels, 1)
  } finally {
    await harness.close()
  }
})
