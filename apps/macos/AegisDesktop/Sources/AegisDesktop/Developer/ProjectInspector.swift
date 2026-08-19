import Foundation

struct ProjectGitSnapshot: Codable, Equatable {
  let branch: String
  let changedFiles: [String]
  var clean: Bool { changedFiles.isEmpty }
}

enum ProjectInspector {
  static func branch(at url: URL) throws -> String {
    try ProjectCommandPolicy.run("/usr/bin/git", ["branch", "--show-current"], at: url)
  }
  static func status(at url: URL) throws -> String {
    try ProjectCommandPolicy.run("/usr/bin/git", ["status", "--short", "--branch"], at: url)
  }
  static func changedFiles(at url: URL) throws -> [String] {
    let text = try ProjectCommandPolicy.run("/usr/bin/git", ["status", "--short"], at: url)
    return text.split(separator: "\n").prefix(ProjectCommandPolicy.maximumChangedFiles).map(String.init)
  }
  static func diffSummary(at url: URL) throws -> String {
    try ProjectCommandPolicy.run("/usr/bin/git", ["diff", "--stat"], at: url)
  }
  static func recentCommits(at url: URL, count: Int = 5) throws -> String {
    let bounded = max(1, min(count, ProjectCommandPolicy.maximumCommits))
    return try ProjectCommandPolicy.run("/usr/bin/git",
      ["log", "-n", String(bounded), "--pretty=format:%h%x09%ad%x09%s", "--date=short"], at: url)
  }
  static func snapshot(at url: URL) throws -> ProjectGitSnapshot {
    ProjectGitSnapshot(branch: try branch(at: url), changedFiles: try changedFiles(at: url))
  }
}
