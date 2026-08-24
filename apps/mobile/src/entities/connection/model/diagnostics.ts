import type { ConnectionState } from "./types";

export interface ConnectionDiagnostics { gateway: string; authentication: string; desktopBridge: string }

// Safe diagnostics derived from the connection state alone -- never a credential or token.
export function connectionDiagnostics(state: ConnectionState): ConnectionDiagnostics {
  const gatewayUnreachable = state === "gatewayUnavailable" || state === "gatewayServerError";
  const authentication = state === "deviceCredentialInvalid" ? "기기 등록 필요"
    : state === "deviceRevoked" ? "연결 해제됨" : state === "deviceDisabled" ? "비활성화됨"
    : state === "authenticationFailed" ? "인증 실패" : gatewayUnreachable ? "확인 불가" : "connected";
  return { gateway: gatewayUnreachable ? "연결 안 됨" : "reachable", authentication,
    desktopBridge: state === "desktopUnavailable" ? "unavailable" : gatewayUnreachable ? "확인 불가" : "reachable" };
}
