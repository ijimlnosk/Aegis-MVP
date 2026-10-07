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
    let state = report.clean ? "변경 없음" : "변경 파일 \(report.changedFileCount)개"
    var sections = ["\(report.project) · \(report.branch.isEmpty ? "브랜치 알 수 없음" : report.branch) · \(state)"]
    if !report.changedFiles.isEmpty {
      sections.append("변경 파일\n" + MessageSegments.code(report.changedFiles.joined(separator: "\n")))
    }
    sections.append(report.recentCommits.isEmpty ? "최근 커밋 없음"
      : "최근 커밋\n" + MessageSegments.code(TextTable.columns(report.recentCommits)))
    return sections.joined(separator: "\n\n")
  }
}
