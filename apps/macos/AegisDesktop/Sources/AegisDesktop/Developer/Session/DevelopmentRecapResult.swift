import Foundation

enum DevelopmentProjectState: String, Codable, Equatable { case clean, dirty }
enum DevelopmentRecapExecutionStatus: String, Equatable { case succeeded, failed }

struct DevelopmentRecapResult: Equatable {
  let project: String
  let executionStatus: DevelopmentRecapExecutionStatus
  let branch: String
  let projectState: DevelopmentProjectState
  let changedFiles: [String]
  let recentCommits: String?
  let sessionSummary: String?
  let recentAutonomousTask: AutonomousDevelopmentHistory?
  let warnings: [String]
}

enum DevelopmentRecapFormatter {
  static func format(_ result: DevelopmentRecapResult) -> String {
    let workingTree = result.projectState == .clean ? "clean" : "변경 \(result.changedFiles.count)개"
    var lines = ["\(result.project) 개발 상태", "Branch: \(result.branch.isEmpty ? "알 수 없음" : result.branch)",
      "Working tree: \(workingTree)"]
    if !result.changedFiles.isEmpty { lines += ["", "변경 파일:"] + result.changedFiles }
    lines += ["", "최근 커밋:", result.recentCommits ?? "확인할 수 없음"]
    if let session = result.sessionSummary { lines += ["", "Aegis 활동:", session] }
    if let task = result.recentAutonomousTask {
      lines += ["", "최근 Aegis 작업:", "- \(task.title)", "- outcome: \(task.outcome.rawValue)",
        "- validation: \(task.validationSummary.isEmpty ? "없음" : task.validationSummary)",
        "- timestamp: \(task.timestamp.formatted())"]
    }
    if !result.warnings.isEmpty { lines += ["", "참고:"] + result.warnings.map { "- \($0)" } }
    return lines.joined(separator: "\n")
  }
}
