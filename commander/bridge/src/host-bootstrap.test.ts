import assert from "node:assert/strict"
import test from "node:test"
import { commanderPanelFromHostBootstrap, installHostOperatorBootstrap, resetHostOperatorBootstrapForTest } from "./host-bootstrap.ts"
import { CommanderMainProcessPanel } from "./main-process-panel.ts"

test("host bootstrap defaults closed and cannot be replaced", () => {
  resetHostOperatorBootstrapForTest()
  assert.deepEqual(commanderPanelFromHostBootstrap().snapshot(), { status: "not-configured", events: [] })
  const panel = new CommanderMainProcessPanel(undefined)
  installHostOperatorBootstrap({ createPanel: () => panel })
  assert.equal(commanderPanelFromHostBootstrap(), panel)
  assert.throws(() => installHostOperatorBootstrap({ createPanel: () => new CommanderMainProcessPanel(undefined) }), /already installed/)
  resetHostOperatorBootstrapForTest()
})
