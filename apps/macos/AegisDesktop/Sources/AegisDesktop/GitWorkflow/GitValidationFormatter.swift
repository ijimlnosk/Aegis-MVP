import Foundation

enum GitValidationFormatter {
  static func format(_ report: ProjectValidationReport, failedCommit: Bool = false) -> String {
    var lines = ["\(report.project) 커밋 검증 \(headline(report.overall))", ""]
    for check in ProjectValidationCheck.allCases {
      guard let result = report.checks.first(where: { $0.check == check }) else { continue }
      lines += ["\(check.rawValue):", label(result)]
      if result.executionStatus == .failed || result.executionStatus == .notRun,
         !result.summary.isEmpty { lines.append(result.summary) }
      lines.append("")
    }
    if failedCommit {
      lines += ["커밋은 생성하지 않았습니다.", "", "Codex로 이 검증 오류를 수정할까요?"]
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func headline(_ value: ValidationOverallResult) -> String {
    switch value {
    case .passed: "통과"
    case .passedWithWarnings: "통과 (경고 있음)"
    case .failed: "실패"
    case .unavailable: "확인 불가"
    }
  }

  private static func label(_ result: ProjectValidationResult) -> String {
    switch result.executionStatus {
    case .passed: "통과"
    case .warning: result.warningCount > 0 ? "경고 \(result.warningCount)건 (오류 0건)" : "경고"
    case .failed: result.exitCode.map { "실패 (exit \($0))" } ?? "실패"
    case .notRun: result.supportStatus == .unsupported ? "지원하지 않음" : "실행하지 못함"
    }
  }
}
