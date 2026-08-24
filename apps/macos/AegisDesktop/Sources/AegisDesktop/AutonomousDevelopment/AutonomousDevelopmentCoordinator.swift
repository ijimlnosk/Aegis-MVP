import Foundation

actor AutonomousDevelopmentCoordinator {
  private(set) var phase: AutonomousDevelopmentPhase = .idle
  private(set) var candidate: DevelopmentTaskCandidate?
  private(set) var repairCount = 0
  private(set) var lastResult: AutonomousDevelopmentResult?

  func lastAttributedFiles(project: String) -> [String]? {
    guard let result = lastResult,
      result.candidate.projectName.caseInsensitiveCompare(project) == .orderedSame else { return nil }
    return result.changedFiles
  }
  private var failedFingerprints: [String: Date] = [:]

  func discover(project: String, root: URL, request: String, provider: any CodingAgentProvider,
                coding: CodingTaskCoordinator, repository: MemoryRepository,
                configuration: AutonomousDevelopmentConfiguration,
                untrustedEvidence: [String] = []) async throws -> DevelopmentTaskCandidate {
    phase = .discovery; repairCount = 0
    let snapshot = try CodingGitInspector.snapshot(at: root)
    let validation = lightweightValidation(project: project, root: root, repository: repository)
    let failures = validation.filter { $0.status == .failed }.map { String($0.summary.prefix(1_500)) }
    let task = CodingTask(project: project, projectRoot: root,
      request: "Find exactly one small, concrete, worthwhile task. \(request)",
      mode: .readOnlyAnalysis, untrustedEvidence: failures + untrustedEvidence.prefix(1))
    let result = try await coding.run(task, provider: provider,
      configuration: .load(), repository: repository)
    guard let selected = DevelopmentTaskDiscovery.candidate(from: result, snapshot: snapshot,
      validation: validation, exclusions: DevelopmentTaskPolicy.exclusions(in: request)) else {
      throw AutonomousDevelopmentError.noCandidate
    }
    guard DevelopmentTaskPolicy.isExecutable(selected, configuration: configuration) else {
      throw AutonomousDevelopmentError.scopeRejected
    }
    if let failedAt = failedFingerprints[selected.fingerprint],
      Date().timeIntervalSince(failedAt) < 86_400 { throw AutonomousDevelopmentError.cooldown }
    candidate = selected; phase = .awaitingApproval
    return selected
  }

  func execute(_ selected: DevelopmentTaskCandidate, root: URL,
               provider: any CodingAgentProvider, coding: CodingTaskCoordinator,
               repository: MemoryRepository,
               configuration: AutonomousDevelopmentConfiguration) async throws -> AutonomousDevelopmentResult {
    guard candidate?.id == selected.id else { throw AutonomousDevelopmentError.staleCandidate }
    guard DevelopmentTaskPolicy.isExecutable(selected, configuration: configuration) else {
      throw AutonomousDevelopmentError.scopeRejected
    }
    phase = .coding
    let task = CodingTask(project: selected.projectName, projectRoot: root,
      request: selected.title, mode: .workspaceWrite,
      untrustedEvidence: [selected.summary] + selected.evidence)
    let first = try await coding.run(task, provider: provider,
      configuration: .init(timeout: CodingConfiguration.load().timeout,
        maximumChangedFiles: configuration.maximumChangedFiles), repository: repository)
    phase = .validating
    var final = first; var repaired = false
    if first.status == .failedValidation, configuration.repairAttempts > 0,
      first.changedFiles.count <= configuration.maximumChangedFiles {
      phase = .repairing; repairCount = 1; repaired = true
      let failures = first.verification.filter { $0.status == .failed }
        .map { String($0.summary.prefix(1_500)) }
      let repair = CodingTask(project: selected.projectName, projectRoot: root,
        request: "Repair validation failures for the same approved task only: \(selected.title)",
        mode: .workspaceWrite, untrustedEvidence: failures + selected.evidence)
      final = try await coding.run(repair, provider: provider,
        configuration: .init(timeout: CodingConfiguration.load().timeout,
          maximumChangedFiles: configuration.maximumChangedFiles), repository: repository)
    }
    let combined = Array(Set(first.changedFiles + (repaired ? final.changedFiles : []))).sorted()
    let approvedPaths = Set(first.changedFiles + selected.evidence.compactMap { evidence in
      evidence.split(separator: ":").first.map(String.init)
    })
    let scopeExpanded = repaired && final.changedFiles.contains { !approvedPaths.contains($0) }
    let status = AutonomousDevelopmentOutcomePolicy.resolve(first: first.status,
      final: final.status, repaired: repaired, changedCount: combined.count,
      limit: configuration.maximumChangedFiles,
      scopeExpanded: scopeExpanded)
    let result = AutonomousDevelopmentResult(candidate: selected, status: status,
      changedFiles: combined, validation: final.verification,
      preexistingCount: first.preexistingFiles.count, repairAttempted: repaired,
      provider: provider.name)
    if ![.succeeded, .succeededWithWarnings].contains(status) { failedFingerprints[selected.fingerprint] = .now }
    lastResult = result; phase = .complete
    return result
  }

  func reject() { phase = .complete }
  func status(configuration: AutonomousDevelopmentConfiguration) -> String {
    ["자율 개발", "- enabled: yes", "- project: \(candidate?.projectName ?? "none")",
      "- task: \(candidate?.title ?? "none")", "- phase: \(phase.rawValue)",
      "- repair count: \(repairCount)", "- max changed files: \(configuration.maximumChangedFiles)",
      "- last result: \(lastResult?.status.rawValue ?? "none")"].joined(separator: "\n")
  }

  private func lightweightValidation(project: String, root: URL,
                                     repository: MemoryRepository) -> [ProjectValidationResult] {
    guard let package = try? PackageScriptTool.inspect(at: root), package.scripts.contains("typecheck") else { return [] }
    return [ProjectValidationRunner.run(.typecheck, project: project, at: root)]
  }

}

enum AutonomousDevelopmentError: LocalizedError {
  case noCandidate, cooldown, staleCandidate, scopeRejected
  var errorDescription: String? {
    switch self {
    case .noCandidate: "자율 실행에 적합한 작은 작업을 찾지 못했습니다."
    case .cooldown: "최근 실패한 동일 작업은 자동으로 다시 시도하지 않습니다."
    case .staleCandidate: "승인된 개발 작업 후보가 더 이상 유효하지 않습니다."
    case .scopeRejected: "예상 범위가 자율 개발 제한을 벗어나 실행하지 않았습니다."
    }
  }
}
