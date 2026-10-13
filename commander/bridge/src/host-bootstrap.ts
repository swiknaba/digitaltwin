import { CommanderMainProcessPanel } from "./main-process-panel.ts"

/**
 * Installed by the operator-owned desktop host before GUI extensions start. This
 * module deliberately has no filesystem, environment, project-setting, or renderer
 * input API: the host closes over its verified identity and proof exchanger.
 */
export interface HostOperatorBootstrap {
  createPanel(): CommanderMainProcessPanel
}

type BootstrapState = { bootstrap: HostOperatorBootstrap | undefined }

// Electron's main bundle loads built-in extension entries lazily. Rollup may place
// this module in both the desktop entry and an extension chunk, so module-local
// state would make a trusted host bootstrap invisible to the Commander extension.
// This process-only symbol keeps the singleton shared across those chunks without
// creating a renderer, project, filesystem, or environment configuration path.
const bootstrapStateKey = Symbol.for("@digitaltwin/commander-bridge/host-bootstrap")

function bootstrapState(): BootstrapState {
  const state = globalThis as Record<symbol, BootstrapState | undefined>
  return state[bootstrapStateKey] ??= { bootstrap: undefined }
}

/** A second installation is rejected so a later extension cannot replace the host bootstrap. */
export function installHostOperatorBootstrap(input: HostOperatorBootstrap): void {
  const state = bootstrapState()
  if (state.bootstrap !== undefined) throw new Error("Commander host bootstrap is already installed")
  state.bootstrap = input
}

/** GUI code fails closed until the trusted desktop host installed a bootstrap. */
export function commanderPanelFromHostBootstrap(): CommanderMainProcessPanel {
  return bootstrapState().bootstrap?.createPanel() ?? new CommanderMainProcessPanel(undefined)
}

/** Test-only reset; production code must never clear an installed host bootstrap. */
export function resetHostOperatorBootstrapForTest(): void {
  bootstrapState().bootstrap = undefined
}
