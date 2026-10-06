import Foundation

/// Plain-language effect and button verb for an approval, matching the phone app's approval card.
struct ApprovalPresentation: Equatable {
  let effect: String
  let confirmLabel: String
  /// Leaves the Mac (message, push, server) or discards work, so it is shown in red.
  let irreversible: Bool

  static func present(kind: String?) -> ApprovalPresentation {
    guard let kind else { return fallback }
    if let known = known[kind] { return known }
    if kind.hasPrefix("run_project_") { return .init(effect: "프로젝트의 package.json 스크립트를 실행합니다.", confirmLabel: "실행", irreversible: false) }
    if kind.contains("_ui_") || kind.hasPrefix("press_") || kind.hasPrefix("select_menu") { return ui }
    return fallback
  }

  private static let fallback = ApprovalPresentation(effect: "Mac에서 변경 작업을 실행합니다.", confirmLabel: "승인", irreversible: false)
  private static let ui = ApprovalPresentation(effect: "Mac 화면에서 버튼·입력을 조작합니다.", confirmLabel: "진행", irreversible: false)
  private static let coding = ApprovalPresentation(effect: "Codex가 프로젝트 코드를 수정하고 검증합니다.", confirmLabel: "수정 시작", irreversible: false)
  private static let known: [String: ApprovalPresentation] = [
    "kakao_message": .init(effect: "카카오톡 메시지를 실제로 보냅니다.", confirmLabel: "보내기", irreversible: true),
    "push_current_branch": .init(effect: "커밋을 원격 저장소에 push합니다.", confirmLabel: "Push", irreversible: true),
    "start_docker_container": .init(effect: "서버 컨테이너를 시작합니다.", confirmLabel: "시작", irreversible: true),
    "stop_docker_container": .init(effect: "서버 컨테이너를 중지합니다.", confirmLabel: "중지", irreversible: true),
    "restart_docker_container": .init(effect: "서버 컨테이너를 재시작합니다.", confirmLabel: "재시작", irreversible: true),
    "rollback_coding_task": .init(effect: "코딩 작업으로 바뀐 파일을 되돌립니다.", confirmLabel: "되돌리기", irreversible: true),
    "close_application": .init(effect: "앱을 종료합니다. 저장하지 않은 작업이 사라질 수 있습니다.", confirmLabel: "종료", irreversible: true),
    "create_commit": .init(effect: "로컬 커밋을 만듭니다. push는 하지 않습니다.", confirmLabel: "커밋", irreversible: false),
    "execute_coding_task": coding, "execute_development_task": coding,
    "repair_development_task": .init(effect: "Codex가 실패한 검증을 고칩니다.", confirmLabel: "수정 시작", irreversible: false),
    "verify_coding_task": .init(effect: "프로젝트의 검증 스크립트를 실행합니다.", confirmLabel: "실행", irreversible: false),
    "open_application": .init(effect: "앱을 엽니다.", confirmLabel: "열기", irreversible: false),
    "open_project": .init(effect: "프로젝트를 엽니다.", confirmLabel: "열기", irreversible: false),
    "close_window": .init(effect: "창을 닫습니다.", confirmLabel: "닫기", irreversible: false),
    "browser_search": .init(effect: "브라우저에서 검색합니다.", confirmLabel: "검색", irreversible: false),
    "set_clipboard": .init(effect: "클립보드 내용을 바꿉니다.", confirmLabel: "변경", irreversible: false),
    "ui_workflow_preflight": ui,
    "skill_save": .init(effect: "이 작업 순서를 Skill로 저장합니다.", confirmLabel: "저장", irreversible: false),
  ]
}
