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

  static var helpText: String { AegisGuide.text() }
}
