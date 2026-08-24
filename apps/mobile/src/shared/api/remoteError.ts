export type RemoteErrorCode = "gatewayUnavailable" | "desktopUnavailable" | "deviceCredentialInvalid" |
  "deviceRevoked" | "deviceDisabled" | "authenticationFailed" | "gatewayServerError" |
  "approvalExpired" | "commandNotFound" | "commandFailed" | "validationFailed" |
  "serverAgentUnavailable" | "codingAgentUnavailable";

export class RemoteError extends Error {
  constructor(readonly code: RemoteErrorCode, message: string) { super(message); }
}

// Codes for which the stored device credential is the problem, not the Gateway itself:
// the credential should be discarded (keeping the Gateway URL) and the user routed back
// to device registration, instead of being reported as a connectivity failure.
export function requiresReRegistration(code: RemoteErrorCode | string) {
  return code === "deviceCredentialInvalid" || code === "deviceRevoked" || code === "deviceDisabled";
}

export function errorMessage(code: RemoteErrorCode) {
  return ({ gatewayUnavailable: "Gateway에 연결할 수 없습니다. Tailscale 연결 상태를 확인하세요.",
    desktopUnavailable: "Mac의 AegisDesktop에 연결할 수 없습니다.", deviceCredentialInvalid: "기기 등록이 필요합니다.",
    deviceRevoked: "이 기기의 원격 연결이 해제되었습니다.", deviceDisabled: "이 기기의 원격 연결이 비활성화되었습니다.",
    commandNotFound: "이전 작업 상태를 찾을 수 없어 작업을 종료했습니다. 다시 요청해 주세요.",
    authenticationFailed: "기기 인증에 실패했습니다.", gatewayServerError: "Gateway 서버에 오류가 발생했습니다. 잠시 후 다시 시도하세요.",
    approvalExpired: "승인 시간이 만료되었습니다.", commandFailed: "작업을 완료하지 못했습니다.",
    validationFailed: "검증이 실패했습니다.", serverAgentUnavailable: "Server Agent에 연결할 수 없습니다.",
    codingAgentUnavailable: "Codex를 사용할 수 없습니다." })[code];
}
