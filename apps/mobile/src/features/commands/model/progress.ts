// Accepts a plain string (not just ProgressPhase) because the value ultimately comes
// from server JSON at runtime, with no guarantee it matches this build's known set --
// an unrecognized non-terminal phase must read as "in progress", never as failure.
export function progressLabel(phase: string) {
  return ({ queued: "작업을 준비하고 있습니다...", planning: "요청을 이해하고 계획을 세우고 있습니다...",
    running: "작업을 진행하고 있습니다...", analyzing: "Codex가 코드를 분석하고 있습니다...",
    coding: "Codex가 코드를 수정하고 있습니다...", validating: "변경사항을 검증하고 있습니다...",
    repairing: "검증 오류를 수정하고 있습니다...", gitPlanning: "커밋 계획을 만들고 있습니다...",
    committing: "커밋을 생성하고 있습니다...", pushing: "원격 저장소에 반영하고 있습니다...",
    screenAnalyzing: "화면을 확인하고 있습니다...", serverChecking: "서버 상태를 확인하고 있습니다...",
    awaitingApproval: "승인을 기다리고 있습니다.", completed: "작업을 완료했습니다.",
    failed: "작업을 완료하지 못했습니다.", cancelled: "작업이 취소되었습니다." } as Record<string, string>)[phase]
    ?? "작업을 진행하고 있습니다...";
}
export function elapsedText(seconds: number) {
  return seconds < 60 ? `${seconds}초` : `${Math.floor(seconds / 60)}분 ${seconds % 60}초`;
}
export function pollDelay(attempt: number, approval: boolean) {
  return approval ? 3_000 : attempt < 10 ? 1_000 : attempt < 30 ? 2_000 : 3_000;
}
// Bounded backoff for the idle connection-recovery loop: 3s, 5s, 10s, then capped at 15s.
export function reconnectDelay(attempt: number) {
  return attempt <= 1 ? 3_000 : attempt === 2 ? 5_000 : attempt === 3 ? 10_000 : 15_000;
}
