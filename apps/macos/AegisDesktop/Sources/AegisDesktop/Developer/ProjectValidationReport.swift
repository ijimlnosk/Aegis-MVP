import Foundation

enum ValidationSupportStatus: String, Codable { case supported, unsupported, skipped }
enum ValidationExecutionStatus: String, Codable { case passed, failed, warning, notRun }
enum ValidationSeverity: String, Codable { case information, warning, error }
enum ValidationOverallResult: String, Codable { case passed, passedWithWarnings, failed, unavailable }

struct ProjectValidationReport: Codable, Equatable {
  let project: String
  let profile: ProjectValidationProfile
  let checks: [ProjectValidationResult]
  let overall: ValidationOverallResult
  let validatedAt: Date

  var allowsCommit: Bool { [.passed, .passedWithWarnings].contains(overall) }

  static func make(project: String, profile: ProjectValidationProfile,
                   checks: [ProjectValidationResult], at date: Date = .now) -> Self {
    let required = checks.filter { profile.requiredChecks.contains($0.check) }
    let unavailable = required.contains { $0.executionStatus == .notRun }
    let failed = checks.contains { $0.executionStatus == .failed }
    let warnings = checks.contains { $0.executionStatus == .warning }
    let overall: ValidationOverallResult = failed ? .failed
      : unavailable ? .unavailable : warnings ? .passedWithWarnings : .passed
    return .init(project: project, profile: profile, checks: checks,
      overall: overall, validatedAt: date)
  }

  static func documentationOnly(project: String) -> Self {
    let checks = ProjectValidationCheck.allCases.map {
      ProjectValidationResult(check: $0, status: .skipped,
        summary: "문서 전용 변경이라 검사를 실행하지 않았습니다.")
    }
    return .init(project: project, profile: .init(requiredChecks: [], optionalChecks: []),
      checks: checks, overall: .passed, validatedAt: .now)
  }
}

enum ProjectValidationService {
  static func run(project: String, root: URL,
                  repository: MemoryRepository) -> ProjectValidationReport {
    let package: ProjectPackage
    do {
      package = try PackageScriptTool.inspect(at: root)
    } catch {
      let profile = ProjectValidationProfile(requiredChecks: [.typecheck, .test], optionalChecks: [])
      let checks = ProjectValidationCheck.allCases.map {
        ProjectValidationResult(check: $0, status: .skipped,
          summary: "package.json validation profile을 확인할 수 없습니다: \(error.localizedDescription)")
      }
      return .make(project: project, profile: profile, checks: checks)
    }
    let profile = ProjectValidationProfile.resolve(project: project, package: package,
      repository: repository)
    let results = profile.allChecks.map { ProjectValidationRunner.run($0, project: project, at: root) }
      + profile.unsupportedChecks.map { ProjectValidationResult(check: $0, status: .unsupported,
        summary: "package.json에 \($0.rawValue) 스크립트가 없어 지원하지 않습니다.") }
    let ordered = ProjectValidationCheck.allCases.compactMap { check in results.first { $0.check == check } }
    return .make(project: project, profile: profile, checks: ordered)
  }
}
