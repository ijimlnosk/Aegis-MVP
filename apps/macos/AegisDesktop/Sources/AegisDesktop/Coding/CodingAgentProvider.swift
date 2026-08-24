import Foundation

enum CodingProviderEvent: String, Codable, Sendable, Equatable {
  case started, analyzing, resultReceived, completed, failed
}

struct CodingProviderDiagnostics: Codable, Sendable, Equatable {
  let exitStatus: Int32?
  let sandboxMode: String
  let stderrSummary: String?
  let eventCount: Int
}

struct CodingAgentExecution: Sendable, Equatable {
  let completed: Bool
  let userResult: String
  let diagnostics: CodingProviderDiagnostics
  let providerEvents: [CodingProviderEvent]
  let timedOut: Bool
  let cancelled: Bool
}

protocol CodingAgentProvider: Sendable {
  var name: String { get }
  var identifier: CodingAgentProviderID { get }
  var executablePath: String { get }
  func version() -> String?
  func isAvailable() -> Bool
  func execute(_ task: CodingTask, policy: CodingExecutionPolicy,
               timeout: TimeInterval) async -> CodingAgentExecution
}

extension CodingAgentProvider {
  var identifier: CodingAgentProviderID { .codex }
  var executablePath: String { "unavailable" }
  func version() -> String? { nil }
}
