import type { CommandFailureCode } from "./types";

export function failureMessage(code: CommandFailureCode) {
  return ({ desktopUnavailable: "Mac의 AegisDesktop에 연결할 수 없습니다.",
    plannerFailed: "요청을 이해하지 못했습니다.", projectUnavailable: "프로젝트를 찾을 수 없습니다.",
    serverAgentUnavailable: "Server Agent가 응답하지 않습니다.", codingAgentUnavailable: "Codex를 사용할 수 없습니다.",
    validationFailed: "검증이 실패했습니다.", approvalExpired: "승인 시간이 만료되었습니다.",
    commandCancelled: "작업이 취소되었습니다.", timeout: "작업 시간이 초과되었습니다.",
    internalError: "작업을 완료하지 못했습니다." })[code];
}

// The single place that decides what text a terminal command shows. Order of
// preference: the real backend message(s), then a typed failureCode reason,
// then a neutral status-appropriate fallback -- never a bare enum word.
export function terminalCommandContent(command: { status: string; messages: string[]; failureCode?: CommandFailureCode }) {
  const joined = command.messages.join("\n").trim();
  if (joined) return joined;
  if (command.failureCode) return failureMessage(command.failureCode);
  if (command.status === "completed") return "작업이 완료되었습니다.";
  if (command.status === "cancelled") return "작업이 취소되었습니다.";
  return failureMessage("internalError");
}
