import { CommanderMainProcessPanel } from "./main-process-panel.ts"

/**
 * Installed by the operator-owned desktop host before GUI extensions start. This
 * module deliberately has no filesystem, environment, project-setting, or renderer
 * input API: the host closes over its verified identity and proof exchanger.
 */
export interface HostOperatorBootstrap {
  createPanel(): CommanderMainProcessPanel
}

let bootstrap: HostOperatorBootstrap | undefined

/** A second installation is rejected so a later extension cannot replace the host bootstrap. */
export function installHostOperatorBootstrap(input: HostOperatorBootstrap): void {
  if (bootstrap !== undefined) throw new Error("Commander host bootstrap is already installed")
  bootstrap = input
}

/** GUI code fails closed until the trusted desktop host installed a bootstrap. */
export function commanderPanelFromHostBootstrap(): CommanderMainProcessPanel {
  return bootstrap?.createPanel() ?? new CommanderMainProcessPanel(undefined)
}

/** Test-only reset; production code must never clear an installed host bootstrap. */
export function resetHostOperatorBootstrapForTest(): void {
  bootstrap = undefined
}
