import Foundation

enum CodingRollbackService {
  static func rollback(diff: CodingTaskDiff, at root: URL) throws -> [String] {
    guard diff.rollbackIsolated, !diff.attributableFiles.isEmpty else {
      throw CodingTaskError.unsafeRollback
    }
    for path in diff.rollbackFiles {
      guard isSafeRelative(path), isTracked(path, at: root) else {
        throw CodingTaskError.unsafeRollback
      }
    }
    _ = try ProjectCommandPolicy.run("/usr/bin/git",
      ["restore", "--worktree", "--"] + diff.rollbackFiles, at: root)
    return diff.attributableFiles
  }

  private static func isTracked(_ path: String, at root: URL) -> Bool {
    (try? ProjectCommandPolicy.run("/usr/bin/git", ["ls-files", "--error-unmatch", "--", path], at: root)) != nil
  }
  private static func isSafeRelative(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
  }
}
