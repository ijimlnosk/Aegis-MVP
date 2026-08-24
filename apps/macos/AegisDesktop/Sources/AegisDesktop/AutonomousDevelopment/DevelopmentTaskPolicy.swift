enum DevelopmentTaskPolicy {
  private static let forbidden = ["migration", "마이그레이션", "authentication redesign", "인증 재설계",
    "payment", "결제", "database schema", "db schema", "배포", "deploy", "multi-project", "전체 갈아"]

  static func isExecutable(_ candidate: DevelopmentTaskCandidate,
                           configuration: AutonomousDevelopmentConfiguration) -> Bool {
    candidate.estimatedChangedFiles <= configuration.maximumChangedFiles
      && ![.medium, .large].contains(candidate.estimatedScope)
      && candidate.validationAvailability != .none
      && !forbidden.contains(where: { candidate.summary.lowercased().contains($0) })
  }

  static func exclusions(in request: String) -> [String] {
    request.components(separatedBy: [",", "."]).compactMap { phrase in
      guard phrase.contains("제외") || phrase.contains("건드리지 마")
        || phrase.contains("수정하지 마") else { return nil }
      let cleaned = phrase.replacingOccurrences(of: "제외해", with: "")
        .replacingOccurrences(of: "건드리지 마", with: "")
        .replacingOccurrences(of: "수정하지 마", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return cleaned.split(separator: " ").first.map(String.init)?
        .replacingOccurrences(of: "관련은", with: "")
        .replacingOccurrences(of: "기능은", with: "")
        .replacingOccurrences(of: "파일은", with: "")
    }.filter { !$0.isEmpty }
  }

  static func honors(_ candidate: DevelopmentTaskCandidate, exclusions: [String]) -> Bool {
    !exclusions.contains { excluded in
      candidate.title.lowercased().contains(excluded)
        || candidate.summary.lowercased().contains(excluded)
        || candidate.evidence.contains { $0.lowercased().contains(excluded) }
    }
  }
}
