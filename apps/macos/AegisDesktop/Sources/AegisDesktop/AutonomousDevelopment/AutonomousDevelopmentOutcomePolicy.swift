enum AutonomousDevelopmentOutcomePolicy {
  static func resolve(first: CodingTaskStatus, final: CodingTaskStatus,
                      repaired: Bool, changedCount: Int, limit: Int,
                      scopeExpanded: Bool) -> AutonomousDevelopmentStatus {
    if changedCount > limit || scopeExpanded { return .needsReview }
    if repaired {
      if final == .succeeded { return .succeeded }
      if final == .succeededWithWarnings { return .succeededWithWarnings }
      return .repairFailed
    }
    switch first {
    case .succeeded: return .succeeded
    case .succeededWithWarnings: return .succeededWithWarnings
    case .failedValidation: return .failedValidation
    case .timedOut: return .timedOut
    case .cancelled: return .cancelled
    case .agentFailed: return .agentFailed
    case .needsReview: return .needsReview
    }
  }
}
