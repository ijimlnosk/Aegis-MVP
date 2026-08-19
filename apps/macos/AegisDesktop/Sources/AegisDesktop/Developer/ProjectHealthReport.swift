import Foundation

struct ProjectHealthReport: Codable, Equatable {
  let project: String
  let branch: String
  let clean: Bool
  let changedFileCount: Int
  let changedFiles: [String]
  let recentCommits: String
  var validationResults: [ProjectValidationResult] = []
  var warnings: [String] = []
  let generatedAt: Date
}

enum ProjectHealthService {
  static func lightweight(project: String, repository: MemoryRepository) throws -> ProjectHealthReport {
    let url = try ProjectCommandPolicy.projectURL(project, repository: repository)
    let snapshot = try ProjectInspector.snapshot(at: url)
    let warnings = snapshot.clean ? [] : ["커밋되지 않은 변경 파일이 \(snapshot.changedFiles.count)개 있습니다."]
    let preferred = (try? repository.find(type: .preference, key: "recent_commit_count"))?.value
    let count = preferred.flatMap(Int.init) ?? 5
    return ProjectHealthReport(project: project, branch: snapshot.branch, clean: snapshot.clean,
      changedFileCount: snapshot.changedFiles.count, changedFiles: snapshot.changedFiles,
      recentCommits: try ProjectInspector.recentCommits(at: url, count: count), warnings: warnings, generatedAt: .now)
  }

  static func format(_ report: ProjectHealthReport) -> String {
    let state = report.clean ? "clean" : "변경 \(report.changedFileCount)개"
    let files = report.changedFiles.isEmpty ? "없음" : report.changedFiles.joined(separator: "\n")
    return """
    \(report.project) 개발 상태
    Branch: \(report.branch.isEmpty ? "알 수 없음" : report.branch)
    Working tree: \(state)
    변경 파일:
    \(files)
    최근 커밋:
    \(report.recentCommits.isEmpty ? "없음" : report.recentCommits)
    """
  }
}
