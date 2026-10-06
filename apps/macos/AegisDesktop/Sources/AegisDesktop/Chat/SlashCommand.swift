import Foundation

enum SlashCommand: String, CaseIterable {
  case help
  case status
  case projects
  case perf

  var summary: String {
    switch self {
    case .help: "Aegis가 할 수 있는 일과 명령어"
    case .status: "AI 백엔드·원격 제어·코딩 에이전트 상태"
    case .projects: "등록된 프로젝트 목록"
    case .perf: "최근 요청 응답 시간과 AI planner 사용 현황"
    }
  }

  var usage: String { "/\(rawValue)" }

  static func isSlashInput(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
  }

  /// Matches only the leading token, so "/status please" still resolves to `.status`.
  static func parse(_ text: String) -> SlashCommand? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("/") else { return nil }
    let token = trimmed.dropFirst().split(whereSeparator: \.isWhitespace).first ?? ""
    return SlashCommand(rawValue: token.lowercased())
  }

  static func suggestions(for text: String) -> [SlashCommand] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("/"), !trimmed.contains(where: \.isWhitespace) else { return [] }
    let prefix = trimmed.dropFirst().lowercased()
    return allCases.filter { $0.rawValue.hasPrefix(prefix) }
  }
}

enum SlashCommandResolution: Equatable {
  case message(String)
  case plan([AgentAction])
}

enum SlashCommandResolver {
  static let statusActions: [AgentAction] = [.getAIBackendStatus, .getRemoteControlStatus,
    .getCodingAgentStatus]

  static func resolve(_ text: String, projects: [ProjectEntity],
                      timings: () -> [RequestTimingRecord] = { [] }) -> SlashCommandResolution? {
    guard SlashCommand.isSlashInput(text) else { return nil }
    switch SlashCommand.parse(text) {
    case .help: return .message(helpText)
    case .status: return .plan(statusActions)
    case .projects: return .message(projectsText(projects))
    case .perf: return .message(RequestTimingSummary.format(timings()))
    case nil:
      return .message("알 수 없는 명령어입니다. /help 로 사용할 수 있는 명령어를 확인하세요.")
    }
  }

  static func projectsText(_ projects: [ProjectEntity]) -> String {
    guard !projects.isEmpty else {
      return "등록된 프로젝트가 없습니다. \"<프로젝트> 위치 찾아줘\"로 등록할 수 있습니다."
    }
    let lines = projects.map { project in
      project.aliases.isEmpty ? "- \(project.name)"
        : "- \(project.name) (별칭: \(project.aliases.joined(separator: ", ")))"
    }
    return (["등록된 프로젝트"] + lines).joined(separator: "\n")
  }

  static let helpText: String = {
    let commands = SlashCommand.allCases.map { "\($0.usage) — \($0.summary)" }
    return (["Aegis가 할 수 있는 일", "", "명령어"] + commands + ["", capabilities])
      .joined(separator: "\n")
  }()

  private static let capabilities = """
  자연어로 요청하세요. [자동]은 바로 실행, [승인]은 확인 후 실행합니다.
  - 프로젝트·Git [자동]: 상태, 브랜치, 최근 커밋, 변경 파일, diff 요약, 배포 준비 점검
  - 검증 [자동]: typecheck·lint·test·build 실행
  - 코딩 에이전트: 분석·수정 제안 [자동], 수정 실행·롤백 [승인]
  - Git 작업 [승인]: 커밋 계획 후 커밋, 현재 브랜치 push / CI·PR 상태 [자동]
  - 서버: sol-server·Docker 상태와 로그 [자동], 컨테이너 시작·중지·재시작 [승인]
  - Mac: 활성 앱·실행 중인 앱·화면 인식 [자동], 앱·프로젝트 열기·닫기·클립보드 변경 [승인]
  - 창·UI 조작: 창 목록·UI 요소 조회 [자동], 클릭·입력 [승인]
  - 기억: 사실·선호·별칭·프로젝트 기억 [자동], 반복 작업을 Skill로 저장 [승인]
  - 메시지: 카카오톡 전송 [승인]
  """
}
