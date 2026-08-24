import Foundation

enum AutonomousDevelopmentStatus: String, Codable, Sendable {
  case succeeded, succeededWithWarnings, failedValidation, agentFailed
  case timedOut, cancelled, needsReview, repairFailed
}

struct AutonomousDevelopmentResult: Sendable, Equatable {
  let candidate: DevelopmentTaskCandidate
  let status: AutonomousDevelopmentStatus
  let changedFiles: [String]
  let validation: [ProjectValidationResult]
  let preexistingCount: Int
  let repairAttempted: Bool
  let provider: String
}

enum AutonomousDevelopmentPhase: String, Sendable {
  case idle, discovery, awaitingApproval, coding, validating, repairing, complete
}

struct AutonomousDevelopmentHistory: Codable, Sendable, Equatable {
  let candidateId: UUID; let projectId: String; let category: DevelopmentTaskCategory
  let title: String; let outcome: AutonomousDevelopmentStatus; let provider: String
  let changedFileCount: Int; let validationSummary: String
  let repairAttempted: Bool; let timestamp: Date
}
