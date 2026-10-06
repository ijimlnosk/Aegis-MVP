export interface ApprovalPresentation {
  /** What approving actually does, in plain words. */
  effect: string;
  /** Verb for the approve button. */
  confirmLabel: string;
  /** Leaves the Mac (message, push, server) or discards work, so it is shown in red. */
  irreversible: boolean;
}

const PRESENTATIONS: Record<string, ApprovalPresentation> = {
  kakao_message: { effect: "카카오톡 메시지를 실제로 보냅니다.", confirmLabel: "보내기", irreversible: true },
  push_current_branch: { effect: "커밋을 원격 저장소에 push합니다.", confirmLabel: "Push", irreversible: true },
  start_docker_container: { effect: "서버 컨테이너를 시작합니다.", confirmLabel: "시작", irreversible: true },
  stop_docker_container: { effect: "서버 컨테이너를 중지합니다.", confirmLabel: "중지", irreversible: true },
  restart_docker_container: { effect: "서버 컨테이너를 재시작합니다.", confirmLabel: "재시작", irreversible: true },
  rollback_coding_task: { effect: "코딩 작업으로 바뀐 파일을 되돌립니다.", confirmLabel: "되돌리기", irreversible: true },
  create_commit: { effect: "Mac의 프로젝트에 로컬 커밋을 만듭니다. push는 하지 않습니다.", confirmLabel: "커밋", irreversible: false },
  execute_coding_task: { effect: "Codex가 프로젝트 코드를 수정하고 검증합니다.", confirmLabel: "수정 시작", irreversible: false },
  execute_development_task: { effect: "Codex가 프로젝트 코드를 수정하고 검증합니다.", confirmLabel: "수정 시작", irreversible: false },
  repair_development_task: { effect: "Codex가 실패한 검증을 고칩니다.", confirmLabel: "수정 시작", irreversible: false },
  verify_coding_task: { effect: "프로젝트의 검증 스크립트를 실행합니다.", confirmLabel: "실행", irreversible: false },
  open_application: { effect: "Mac에서 앱을 엽니다.", confirmLabel: "열기", irreversible: false },
  open_project: { effect: "Mac에서 프로젝트를 엽니다.", confirmLabel: "열기", irreversible: false },
  close_application: { effect: "Mac에서 앱을 종료합니다. 저장하지 않은 작업이 사라질 수 있습니다.", confirmLabel: "종료", irreversible: true },
  close_window: { effect: "Mac에서 창을 닫습니다.", confirmLabel: "닫기", irreversible: false },
  browser_search: { effect: "Mac 브라우저에서 검색합니다.", confirmLabel: "검색", irreversible: false },
  set_clipboard: { effect: "Mac 클립보드 내용을 바꿉니다.", confirmLabel: "변경", irreversible: false },
  ui_workflow_preflight: { effect: "Mac 화면에서 버튼·입력을 조작합니다.", confirmLabel: "진행", irreversible: false },
};

const SCRIPT_RUN: ApprovalPresentation = { effect: "프로젝트의 package.json 스크립트를 실행합니다.", confirmLabel: "실행", irreversible: false };
const UI_ACTION: ApprovalPresentation = { effect: "Mac 화면에서 버튼·입력을 조작합니다.", confirmLabel: "진행", irreversible: false };
const FALLBACK: ApprovalPresentation = { effect: "Mac에서 변경 작업을 실행합니다.", confirmLabel: "승인", irreversible: false };

export function presentApproval(kind: string): ApprovalPresentation {
  if (PRESENTATIONS[kind]) return PRESENTATIONS[kind];
  if (kind.startsWith("run_project_")) return SCRIPT_RUN;
  if (/_ui_|^press_|^select_menu/.test(kind)) return UI_ACTION;
  return FALLBACK;
}

/** "4분 32초 남음", or undefined once expired or when the time is unknown. */
export function remainingText(expiresAt: string, now: number): string | undefined {
  const left = Math.floor((Date.parse(expiresAt) - now) / 1_000);
  if (!Number.isFinite(left) || left <= 0) return undefined;
  return left >= 60 ? `${Math.floor(left / 60)}분 ${left % 60}초 남음` : `${left}초 남음`;
}
