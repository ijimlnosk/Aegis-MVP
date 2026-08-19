enum DeploymentReadinessState: String, Codable { case ready, warning, blocked, unknown }

struct DeploymentReadiness: Codable, Equatable {
  let state: DeploymentReadinessState
  let passed: [String]
  let warnings: [String]
  let unsupported: [String]
  let blockers: [String]

  static func assess(_ report: ProjectHealthReport, profile: ProjectValidationProfile) -> Self {
    let byCheck = Dictionary(uniqueKeysWithValues: report.validationResults.map { ($0.check, $0) })
    let failed = profile.requiredChecks.compactMap { byCheck[$0] }.filter { $0.status == .failed }
    let unavailable = profile.requiredChecks.filter {
      byCheck[$0]?.status == .skipped || (byCheck[$0] == nil && !profile.unsupportedChecks.contains($0))
    }
    let passed = report.validationResults.filter { $0.status == .passed }.map(\.summary)
    var unsupported = report.validationResults.filter { $0.status == .unsupported }.map(\.summary)
    unsupported += profile.unsupportedChecks.filter { byCheck[$0] == nil }.map {
      "package.json에 \($0.rawValue) 스크립트가 없어 \($0.rawValue) 검사는 제외했습니다."
    }
    var warnings = report.validationResults.filter { $0.status == .warning }.map(\.summary)
    warnings += profile.optionalChecks.compactMap { byCheck[$0] }
      .filter { $0.status == .failed }.map { "선택 검사 실패: \($0.summary)" }
    if !report.clean { warnings.append("working tree에 미커밋 변경이 있습니다.") }
    warnings += profile.requiredChecks.filter { profile.unsupportedChecks.contains($0) }.map {
      "필수 \($0.rawValue) 스크립트가 등록되어 있지 않습니다."
    }
    if !failed.isEmpty {
      return Self(state: .blocked, passed: passed, warnings: warnings,
        unsupported: unsupported, blockers: failed.map(\.summary))
    }
    if !unavailable.isEmpty {
      return Self(state: .unknown, passed: passed, warnings: warnings,
        unsupported: unsupported, blockers: unavailable.map { "\($0.rawValue) 필수 검사를 평가하지 못했습니다." })
    }
    let state: DeploymentReadinessState = warnings.isEmpty ? .ready : .warning
    return Self(state: state, passed: passed, warnings: warnings,
      unsupported: unsupported, blockers: [])
  }
}
