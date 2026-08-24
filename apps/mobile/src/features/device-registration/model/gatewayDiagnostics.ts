import type { GatewayProbeStatus } from "./useGatewayProbe";

export interface GatewayDiagnostics { gateway: string; https: string; authentication: string }

// Safe diagnostics only: reachability/HTTPS/auth-code labels, never credentials or tokens.
export function gatewayDiagnostics(status: GatewayProbeStatus, isHttps: boolean): GatewayDiagnostics | undefined {
  if (status === "idle" || status === "checking") return undefined;
  if (status === "gatewayUnavailable") return { gateway: "연결 안 됨", https: "확인 불가", authentication: "확인 불가" };
  const https = isHttps ? "정상" : "해당 없음 (http)";
  const authentication = ({ connected: "정상", deviceCredentialInvalid: "기기 등록 필요", deviceRevoked: "기기 연결 해제됨",
    deviceDisabled: "기기 비활성화됨", authenticationFailed: "인증 실패", gatewayServerError: "Gateway 서버 오류" } as Record<string, string>)[status]
    ?? "알 수 없음";
  return { gateway: "연결됨", https, authentication };
}
