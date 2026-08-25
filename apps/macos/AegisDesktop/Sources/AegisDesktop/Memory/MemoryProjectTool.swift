import Foundation

enum MemoryProjectTool {
  static func status(project: String, repository: MemoryRepository) throws -> String {
    let path = try ProjectCommandPolicy.projectURL(project, repository: repository)
    let snapshot = try ProjectInspector.snapshot(at: path)
    let changes = snapshot.changedFiles.isEmpty
      ? ["- 변경사항 없음"]
      : snapshot.changedFiles.map { "- \($0)" }
    let commits = (try? ProjectInspector.recentCommits(at: path, count: 3)) ?? ""
    var lines = ["\(project) 작업 현황", "브랜치: \(snapshot.branch.isEmpty ? "분리된 HEAD" : snapshot.branch)", "", "변경 파일:"]
    lines += changes
    if !commits.isEmpty { lines += ["", "최근 커밋:", commits] }
    return lines.joined(separator: "\n")
  }
}

enum MemoryProjectError: LocalizedError {
  case unknownProject(String), invalidPath(String), git(String)

  var errorDescription: String? {
    switch self {
    case .unknownProject(let project): "기억된 프로젝트를 찾지 못했습니다: \(project)"
    case .invalidPath(let path): "기억된 프로젝트 경로를 사용할 수 없습니다: \(path)"
    case .git(let message): "프로젝트 상태 확인 실패: \(message)"
    }
  }
}
