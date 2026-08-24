enum CodingFindingProposalFormatter {
  static func format(_ proposal: CodingTaskProposal) -> String {
    var lines = ["Project: \(proposal.projectName)", "Provider: \(proposal.provider.rawValue)", "", "Goal:", proposal.goal,
      "", "Evidence:"]
    lines += proposal.evidence.isEmpty ? ["- 이전 읽기 전용 분석 결과"]
      : proposal.evidence.map { "- \($0)" }
    lines += ["", "Intended outcome:", proposal.intendedOutcome]
    lines += ["", "Scope:", "trusted project only", "", "Expected validation:"]
    lines += proposal.validationProfile.map { "- \($0)" }
    return lines.joined(separator: "\n")
  }

  static func format(project: String, request: String,
                     finding: CodingFindingContext?) -> String {
    var lines = ["Project: \(project)"]
    if let finding, finding.projectId == project.lowercased() {
      lines += ["Goal: \(finding.title)", "Evidence:"]
      lines += finding.evidenceLocations.isEmpty ? ["- 이전 읽기 전용 분석 결과"]
        : finding.evidenceLocations.prefix(5).map { "- \($0)" }
      lines += ["Intended outcome: \(finding.recommendation)"]
    } else {
      lines += ["Goal: \(String(request.prefix(500)))"]
    }
    lines += ["Scope: trusted project only",
      "Expected validation: typecheck, lint, tests where supported"]
    return lines.joined(separator: "\n")
  }
}
