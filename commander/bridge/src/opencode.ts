/**
 * The maintained OpenCode GUI bundle may import this entry without loading an
 * operator transport, a credential, or user/project configuration. The complete
 * Node-oriented bridge core remains available only through the explicit `./core`
 * subpath for a future reviewed main-process bootstrap.
 */
export function unconfiguredCommanderBridgeStatus(): "not-configured" {
  return "not-configured"
}
