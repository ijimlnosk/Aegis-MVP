enum DevelopmentTaskScorer {
  static func score(_ candidate: DevelopmentTaskCandidate) -> Double {
    let severity: [DevelopmentTaskSeverity: Double] = [.critical: 40, .high: 30, .medium: 20, .low: 10]
    let scope: [DevelopmentTaskScope: Double] = [.tiny: 20, .small: 15, .medium: 5, .large: -30]
    let validation: [ValidationAvailability: Double] = [.strong: 20, .moderate: 12, .weak: 4, .none: -20]
    return (severity[candidate.severity] ?? 0) + candidate.confidence * 30
      + (scope[candidate.estimatedScope] ?? 0) + (validation[candidate.validationAvailability] ?? 0)
      - (candidate.overlapsExistingChanges ? 15 : 0)
  }

  static func best(_ candidates: [DevelopmentTaskCandidate]) -> DevelopmentTaskCandidate? {
    candidates.max { score($0) < score($1) }
  }
}
