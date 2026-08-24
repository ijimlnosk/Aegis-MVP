import Foundation

enum DevelopmentTaskDiscovery {
  static func candidate(from result: CodingTaskResult, snapshot: CodingTaskSnapshot,
                        validation: [ProjectValidationResult], exclusions: [String]) -> DevelopmentTaskCandidate? {
    guard let finding = CodingFindingParser.parse(result: result) else { return nil }
    let text = finding.summary.lowercased()
    let failed = validation.first { $0.status == .failed }
    let category: DevelopmentTaskCategory = failed.map(category(for:)) ?? category(for: text)
    let evidence = failed.map { [String($0.summary.prefix(500))] + finding.evidenceLocations }
      ?? finding.evidenceLocations
    let paths = Set(evidence.compactMap(path))
    let dirty = Set(snapshot.entries.map(\.path))
    let strategy = validation.map(\.check)
    let candidate = DevelopmentTaskCandidate(id: UUID(), projectId: result.project.lowercased(),
      projectName: result.project, category: category, title: String(finding.title.prefix(180)),
      summary: String(finding.summary.prefix(1_500)), evidence: Array(evidence.prefix(8)),
      confidence: failed == nil ? 0.78 : 0.95, severity: failed == nil ? .medium : .high,
      estimatedScope: paths.count <= 1 ? .tiny : .small,
      estimatedChangedFiles: min(max(paths.count, 1), 5),
      validationStrategy: strategy.isEmpty ? [.typecheck, .lint, .test] : strategy,
      validationAvailability: failed == nil ? .moderate : .strong, proposedAt: .now,
      overlapsExistingChanges: !paths.isDisjoint(with: dirty))
    return DevelopmentTaskPolicy.honors(candidate, exclusions: exclusions) ? candidate : nil
  }

  private static func category(for check: ProjectValidationResult) -> DevelopmentTaskCategory {
    switch check.check { case .typecheck: .typeError; case .test: .testFailure; case .lint: .lintIssue; case .build: .bug }
  }

  private static func category(for text: String) -> DevelopmentTaskCategory {
    if text.contains("typeerror") || text.contains("typescript") { return .typeError }
    if text.contains("test") || text.contains("테스트") { return .testFailure }
    if text.contains("lint") { return .lintIssue }
    if text.contains("performance") || text.contains("성능") { return .performanceIssue }
    if text.contains("dead code") || text.contains("미사용") { return .deadCode }
    if text.contains("reliab") || text.contains("안전") { return .reliabilityIssue }
    return .bug
  }

  private static func path(_ evidence: String) -> String? {
    let value = evidence.split(separator: ":").dropLast().joined(separator: ":")
    return value.contains("/") ? value : nil
  }
}
