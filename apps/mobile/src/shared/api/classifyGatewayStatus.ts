import type { RemoteErrorCode } from "./remoteError";

// Turns an HTTP response into a typed Gateway error, never into a connectivity
// verdict: any response we actually received (2xx..5xx) proves the Gateway is
// reachable. Only a fetch()/network failure (see aegisRemoteClient.request) may
// become "gatewayUnavailable" -- see the ticket for the incident this fixes.
export function classifyGatewayStatus(status: number, errorBody?: string): RemoteErrorCode | undefined {
  if (status >= 200 && status < 300) return undefined;
  if (errorBody === "deviceRevoked") return "deviceRevoked";
  if (errorBody === "deviceDisabled") return "deviceDisabled";
  if (errorBody === "approvalExpired") return "approvalExpired";
  if (status === 401) return "deviceCredentialInvalid";
  if (status === 403) return "authenticationFailed";
  if (status === 404) return "commandNotFound";
  if (status >= 500) return "gatewayServerError";
  return "commandFailed";
}
