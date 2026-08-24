import Foundation

// Read-only filesystem search used only to SUGGEST a path back to the user.
// Bounded to a small allowlist of conventional project-root directories (never a
// recursive/whole-disk scan), matches by exact folder name, and requires a `.git`
// directory so it never points at an arbitrary non-project folder. This never
// registers anything by itself -- registration still goes through MemoryStore,
// exactly as if the user had typed the "프로젝트 경로는 ...야" phrase themselves,
// so ProjectEntityResolver's registered-only allowlist is unchanged.
enum ProjectDiscovery {
  static func find(named name: String, searchRoots: [URL]? = nil,
                    fileManager: FileManager = .default) -> String? {
    let target = name.lowercased()
    for root in searchRoots ?? defaultSearchRoots(fileManager: fileManager) {
      guard let entries = try? fileManager.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
      if let match = entries.first(where: { $0.lastPathComponent.lowercased() == target
        && isLikelyProject($0, fileManager: fileManager) }) {
        return match.path
      }
    }
    return nil
  }

  private static func isLikelyProject(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
    return fileManager.fileExists(atPath: url.appendingPathComponent(".git").path)
  }

  private static func defaultSearchRoots(fileManager: FileManager) -> [URL] {
    let home = fileManager.homeDirectoryForCurrentUser
    return [home, home.appendingPathComponent("Developer"), home.appendingPathComponent("Projects"),
      home.appendingPathComponent("Documents")].filter { (try? $0.checkResourceIsReachable()) == true }
  }
}
