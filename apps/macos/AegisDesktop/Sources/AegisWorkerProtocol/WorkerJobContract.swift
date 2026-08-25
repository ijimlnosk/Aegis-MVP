import Foundation

public enum WorkerJobState: String, Codable, Sendable {
  case queued, running, awaitingApproval, completed, failed, cancelled, interrupted
}

public enum WorkerJobRisk: String, Codable, Sendable {
  case readOnly, mutation
}

public enum WorkerRecoveryDecision: String, Codable, Sendable {
  case preserveTerminal
  case observeActiveLease
  case resume
  case failClosed
}

public struct WorkerJobContract: Codable, Sendable {
  public static let schemaVersion = 1
  public let version: Int
  public let commandId: String
  public let sessionId: String
  public let state: WorkerJobState
  public let risk: WorkerJobRisk
  public let approvalGranted: Bool
  public let hasValidationPlan: Bool
  public let leaseExpiresAt: Date?

  public init(version: Int = schemaVersion, commandId: String, sessionId: String,
              state: WorkerJobState, risk: WorkerJobRisk, approvalGranted: Bool,
              hasValidationPlan: Bool, leaseExpiresAt: Date?) {
    self.version = version
    self.commandId = commandId
    self.sessionId = sessionId
    self.state = state
    self.risk = risk
    self.approvalGranted = approvalGranted
    self.hasValidationPlan = hasValidationPlan
    self.leaseExpiresAt = leaseExpiresAt
  }

  public func recoveryDecision(now: Date = .now) -> WorkerRecoveryDecision {
    if [.completed, .failed, .cancelled, .interrupted].contains(state) {
      return .preserveTerminal
    }
    if let leaseExpiresAt, leaseExpiresAt > now { return .observeActiveLease }
    if risk == .readOnly { return .resume }
    return approvalGranted && hasValidationPlan ? .resume : .failClosed
  }
}
