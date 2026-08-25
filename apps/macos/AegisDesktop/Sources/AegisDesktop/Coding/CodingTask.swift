import Foundation

enum CodingTaskMode: String, Codable, Sendable { case readOnlyAnalysis, workspaceWrite }

struct CodingExecutionPolicy: Sendable, Equatable {
  let allowWrites: Bool
  static let readOnly = Self(allowWrites: false)
  static let workspaceWrite = Self(allowWrites: true)
  static func policy(for mode: CodingTaskMode) -> Self {
    mode == .readOnlyAnalysis ? .readOnly : .workspaceWrite
  }
}

struct CodingTask: Identifiable, Codable, Sendable, Equatable {
  let id: UUID
  let project: String
  let projectRoot: URL
  let request: String
  let mode: CodingTaskMode
  let startedAt: Date
  let untrustedEvidence: [String]
  let sourceFindingId: UUID?
  let sourceFindingTitle: String?
  let remoteSessionId: String?
  let remoteCommandId: String?

  init(id: UUID = UUID(), project: String, projectRoot: URL, request: String,
       mode: CodingTaskMode, startedAt: Date = Date(), untrustedEvidence: [String] = [],
       sourceFindingId: UUID? = nil, sourceFindingTitle: String? = nil,
       remoteSessionId: String? = nil, remoteCommandId: String? = nil) {
    self.id = id; self.project = project; self.projectRoot = projectRoot
    self.request = request; self.mode = mode; self.startedAt = startedAt
    self.untrustedEvidence = untrustedEvidence
    self.sourceFindingId = sourceFindingId; self.sourceFindingTitle = sourceFindingTitle
    self.remoteSessionId = remoteSessionId; self.remoteCommandId = remoteCommandId
  }
}

enum CodingTaskStatus: String, Codable, Sendable {
  case succeeded, succeededWithWarnings, failedValidation, agentFailed
  case cancelled, timedOut, needsReview
}

enum CodingExecutionLifecycle: String, Codable, Sendable {
  case planned, validated, started, providerRunning, providerFinished, verified, completed
}

struct CodingTaskResult: Codable, Sendable, Equatable {
  let taskID: UUID
  let project: String
  let status: CodingTaskStatus
  let summary: String
  let changedFiles: [String]
  let verification: [ProjectValidationResult]
  let provider: String
  let duration: TimeInterval
  let hadPreexistingChanges: Bool
  let mode: CodingTaskMode
  let workingTreeDelta: GitWorkingTreeDelta
  let preexistingFiles: [String]
  let lifecycle: CodingExecutionLifecycle
  let providerDiagnostics: CodingProviderDiagnostics
  let providerEvents: [CodingProviderEvent]
  let sourceFindingId: UUID?
  let sourceFindingTitle: String?
}
