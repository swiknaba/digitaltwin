import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

test("treats existing-work follow-ups as results before instructions", async () => {
  const baseline = await readFile(new URL("./commander-agent-baseline.md", import.meta.url), "utf8")
  assert.match(baseline, /first inspect\n+the tracked session's latest progress or reply and report it/)
  assert.match(baseline, /“follow up\non it” after starting a ping as a read\/status request/)
  assert.match(baseline, /“tell it to run tests”/)
  assert.match(baseline, /commander_list_enabled_models/)
  assert.match(baseline, /cheapest tier, such as Haiku/)
  assert.match(baseline, /Reserve the top tier for the main Commander session/)
  assert.match(baseline, /only after matching it to exactly one\n+enabled inventory entry/)
  assert.match(baseline, /It applies to that request only unless the user\n+explicitly asks to retain it/)
  assert.match(baseline, /opaque identifiers in\n+structured tool inputs and results/)
})

test("keeps the active Hermes persona and authenticated handoff aligned with worker policy", async () => {
  const templateSoul = await readFile(new URL("./hermes-profile-template/SOUL.md", import.meta.url), "utf8")
  const gateway = await readFile(new URL("../scripts/local-hermes-gateway", import.meta.url), "utf8")
  assert.match(templateSoul, /call `commander_list_enabled_models` for the target project/)
  assert.match(templateSoul, /cheapest tier, such as Haiku/)
  assert.match(templateSoul, /only when exactly one enabled entry matches, and scope it to that request unless\n+the human explicitly asks to retain it/)
  assert.match(templateSoul, /opaque identifiers in structured tool inputs and results/)
  assert.match(gateway, /ln -sfn "\$profile\/SOUL\.md" "\$handoff_soul"/)
})
