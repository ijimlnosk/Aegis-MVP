import Foundation

enum ValidationStatus: String, Codable { case passed, failed, warning, skipped, unsupported }
enum ProjectValidationCheck: String, Codable, CaseIterable { case typecheck, lint, test, build }

struct ProjectValidationResult: Codable, Equatable {
  let check: ProjectValidationCheck
  let status: ValidationStatus
  let summary: String
  let warningCount: Int

  init(check: ProjectValidationCheck, status: ValidationStatus,
       summary: String, warningCount: Int = 0) {
    self.check = check; self.status = status; self.summary = summary
    self.warningCount = warningCount
  }
  var succeedsPlan: Bool { status != .failed }
}

struct ProjectValidationProfile: Codable, Equatable {
  let requiredChecks: [ProjectValidationCheck]
  let optionalChecks: [ProjectValidationCheck]
  var unsupportedChecks: [ProjectValidationCheck] = []

  var allChecks: [ProjectValidationCheck] {
    ProjectValidationCheck.allCases.filter { requiredChecks.contains($0) || optionalChecks.contains($0) }
  }

  static func resolve(project: String, package: ProjectPackage,
                      repository: MemoryRepository) -> Self {
    let available = ProjectValidationCheck.allCases.filter { package.scripts.contains($0.rawValue) }
    let key = "project_validation_profile:\(project.lowercased())"
    let configured = (try? repository.find(type: .preference, key: key))?.value
      .split(separator: ",").compactMap { ProjectValidationCheck(rawValue: $0.trimmingCharacters(in: .whitespaces)) } ?? []
    let unsupported = ProjectValidationCheck.allCases.filter { !available.contains($0) }
    if !configured.isEmpty {
      return Self(requiredChecks: configured, optionalChecks: available.filter { !configured.contains($0) },
        unsupportedChecks: unsupported)
    }
    let required = available.filter { [.typecheck, .test].contains($0) }
    return Self(requiredChecks: required, optionalChecks: available.filter { !required.contains($0) },
      unsupportedChecks: unsupported)
  }
}

enum ProjectValidationRunner {
  static func run(_ check: ProjectValidationCheck, project: String, at url: URL) -> ProjectValidationResult {
    do {
      let output = try PackageScriptTool.run(check.rawValue, at: url)
      if check == .lint, let warnings = lintWarnings(output), warnings > 0 {
        return .init(check: check, status: .warning,
          summary: "ESLint 오류 없이 경고 \(warnings)건이 있습니다.", warningCount: warnings)
      }
      return .init(check: check, status: .passed, summary: "\(check.rawValue) 검사가 통과했습니다.")
    } catch ProjectCommandError.unsupportedScript {
      return .init(check: check, status: .unsupported,
        summary: "\(project)에는 \(check.rawValue) 스크립트가 없어 \(check.rawValue) 검사를 건너뜁니다.")
    } catch ProjectCommandError.commandFailed(let detail) {
      return .init(check: check, status: .failed,
        summary: detail.trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
      return .init(check: check, status: .skipped,
        summary: "\(check.rawValue) 검사 도구를 실행할 수 없습니다: \(error.localizedDescription)")
    }
  }

  private static func lintWarnings(_ output: String) -> Int? {
    let pattern = #"([0-9]+)\s+warnings?"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
      let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
      let range = Range(match.range(at: 1), in: output) else { return nil }
    return Int(output[range])
  }
}
