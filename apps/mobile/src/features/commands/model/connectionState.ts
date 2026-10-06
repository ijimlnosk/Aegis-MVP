import { RemoteError } from "@/shared/api/remoteError";
import type { ConnectionState } from "@/entities/connection/model/types";

// "connected" is the only state the idle reconnect loop treats as settled; every other
// outcome (gatewayServerError, gatewayUnavailable, authenticationFailed, desktopUnavailable, ...)
// keeps retrying with backoff instead of leaving a stale error on screen forever.
export const SETTLED_CONNECTION: ReadonlySet<string> = new Set(["connected"]);

// Only connectivity/auth-shaped errors may change the connection indicator.
// A per-command domain error (approvalExpired, validationFailed, ...) still means
// the Gateway answered fine, so it leaves the connection state as "connected".
const CONNECTIVITY_CODES: ReadonlySet<string> = new Set([
  "gatewayUnavailable", "desktopUnavailable", "deviceCredentialInvalid",
  "deviceRevoked", "deviceDisabled", "authenticationFailed", "gatewayServerError",
]);

export function connectionStateFor(error: unknown): ConnectionState {
  if (error instanceof RemoteError) return CONNECTIVITY_CODES.has(error.code) ? error.code as ConnectionState : "connected";
  return "gatewayUnavailable";
}
