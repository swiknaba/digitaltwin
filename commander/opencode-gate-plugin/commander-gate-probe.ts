const probeId = "digitaltwin-commander-gate-probe"

// OpenCode v2.0.27 rejects the current documented named-function plugin shape.
// Its installed loader requires this default definition shape instead.
const commanderGateProbe = {
  id: probeId,
  setup: () => {
    console.info(`${probeId}: loaded`)
  },
}

export default commanderGateProbe
