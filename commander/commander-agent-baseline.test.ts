import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

test("treats existing-work follow-ups as results before instructions", async () => {
  const baseline = await readFile(new URL("./commander-agent-baseline.md", import.meta.url), "utf8")
  assert.match(baseline, /first inspect\n+the tracked session's latest progress or reply and report it/)
  assert.match(baseline, /“follow up\non it” after starting a ping as a read\/status request/)
  assert.match(baseline, /“tell it to run tests”/)
})
