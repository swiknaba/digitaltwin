import { createHash } from "node:crypto"
import { bridgeRequestId, capabilityPayloadDigest, type CapabilityBinding, type RequestedAction } from "./contract.ts"

/**
 * Produces the canonical command binding shared by the desktop issuer and bridge.
 * The fixed field order makes the digest independent of JSON serialization details.
 */
export function commandCapabilityBinding(action: RequestedAction, rawRequestId: string, text?: string): CapabilityBinding {
  const requestId = bridgeRequestId(rawRequestId)
  const normalizedText = action === "cancel" ? "" : text ?? ""
  const material = `${action}\n${requestId}\n${normalizedText}`
  return { requestId, payloadDigest: capabilityPayloadDigest(createHash("sha256").update(material, "utf8").digest("hex")) }
}
