export type ConnectionState = "disconnected" | "connecting" | "connected" | "reconnecting" |
  "desktopUnavailable" | "deviceCredentialInvalid" | "deviceRevoked" | "deviceDisabled" |
  "authenticationFailed" | "gatewayServerError" | "gatewayUnavailable";

export interface GatewayStatus {
  gateway: "ready";
  desktopBridge: "reachable" | "unavailable" | "unauthorized";
  pendingApprovals: number;
  screenLocked?: boolean | null;
}
