import Foundation

enum CodingAgentProviderID: String, Codable, Sendable, CaseIterable { case codex, claude }

struct CodingAgentProviderConfiguration: Equatable {
  let primary: CodingAgentProviderID
  let fallback: CodingAgentProviderID?
  let claudeTimeout: TimeInterval?

  static func load(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
    let timeout = Double(environment["AEGIS_CLAUDE_CODE_TIMEOUT_SECONDS"] ?? "")
    return .init(primary: .codex, fallback: nil,
      claudeTimeout: timeout.map { min(max($0, 30), 3_600) })
  }
}

enum CodingAgentProviderPolicy {
  static let enabled: CodingAgentProviderID = .codex
  static let unsupportedMessage = "현재 코딩 작업은 Codex만 사용하도록 설정되어 있습니다."
  static func rejects(_ request: String) -> Bool {
    CodingAgentProviderResolver.explicit(in: request) == .claude
  }
}

enum CodingAgentProviderResolver {
  static func explicit(in request: String) -> CodingAgentProviderID? {
    let text = request.lowercased()
    if text.contains("claude") || text.contains("클로드") { return .claude }
    if text.contains("codex") || text.contains("코덱스") { return .codex }
    return nil
  }

  static func resolve(request: String, project: String, repository: MemoryRepository,
                      configuration: CodingAgentProviderConfiguration = .load()) -> CodingAgentProviderID {
    .codex
  }
}

struct CodingAgentProviderPool: Sendable {
  let codex: CodexCodingAgentProvider
  let claude: ClaudeCodeCodingAgentProvider
  let configuration: CodingAgentProviderConfiguration

  init(configuration: CodingAgentProviderConfiguration = .load()) {
    self.configuration = configuration
    codex = .init(); claude = .init()
  }

  init(codex: CodexCodingAgentProvider, claude: ClaudeCodeCodingAgentProvider,
       configuration: CodingAgentProviderConfiguration) {
    self.codex = codex; self.claude = claude; self.configuration = configuration
  }

  func provider(_ id: CodingAgentProviderID) -> any CodingAgentProvider {
    id == .claude ? claude : codex
  }

  func selected(_ id: CodingAgentProviderID) -> any CodingAgentProvider {
    codex
  }
}
