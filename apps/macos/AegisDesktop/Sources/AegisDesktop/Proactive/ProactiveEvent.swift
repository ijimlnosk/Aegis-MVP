import Foundation

enum ProactiveSeverity: String, Codable, Comparable {
  case info, warning, critical
  static func < (lhs: Self, rhs: Self) -> Bool {
    [Self.info, .warning, .critical].firstIndex(of: lhs)! < [Self.info, .warning, .critical].firstIndex(of: rhs)!
  }
}

enum ProactiveEventType: String, Codable {
  case serverUnavailable, serverRecovered, memoryHigh, memoryRecovered
  case diskHigh, diskRecovered, containerStopped, containerRecovered
  case projectUnavailable, projectRecovered, projectDirty, projectClean
  case projectBranchChanged, projectChangesHigh
}

struct ProactiveEvent: Identifiable, Codable, Equatable {
  let id: UUID
  let type: ProactiveEventType
  let severity: ProactiveSeverity
  let source: ContextSourceKind
  let title: String
  let message: String
  let evidence: String
  let createdAt: Date
  let deduplicationKey: String
  let isRecovery: Bool
  let suggestedAction: AgentAction?

  init(id: UUID = UUID(), type: ProactiveEventType, severity: ProactiveSeverity,
       source: ContextSourceKind, title: String, message: String, evidence: String,
       createdAt: Date = .now, deduplicationKey: String, isRecovery: Bool = false,
       suggestedAction: AgentAction? = nil) {
    self.id = id; self.type = type; self.severity = severity; self.source = source
    self.title = title; self.message = message; self.evidence = evidence
    self.createdAt = createdAt; self.deduplicationKey = deduplicationKey
    self.isRecovery = isRecovery; self.suggestedAction = suggestedAction
  }
}
