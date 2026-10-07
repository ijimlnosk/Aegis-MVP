import Foundation

/// Read-only views into a registered project. Only git-tracked files are visible, secret-bearing
/// paths are excluded, and every returned line passes through `SecretRedactor`.
enum ProjectCodeReader {
  static let maximumMatches = 30
  static let maximumLines = 200
  private static let git = "/usr/bin/git"
  private static let secretPathspecs = [":(exclude,glob)**/.env*", ":(exclude,glob)**/*.pem", ":(exclude,glob)**/*.key",
    ":(exclude,glob)**/*.p12", ":(exclude,glob)**/*.keystore", ":(exclude,glob)**/*secret*", ":(exclude,glob)**/*credential*"]

  static func isSecretPath(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent.lowercased()
    return name.hasPrefix(".env") || ["pem", "key", "p12", "keystore", "jks"].contains((name as NSString).pathExtension)
      || name.contains("secret") || name.contains("credential")
  }

  static func search(_ query: String, project: String, root: URL) throws -> String {
    let output: String
    do {
      output = try ProjectCommandPolicy.run(git, ["grep", "-n", "-I", "-i", "-F", "--no-color", "-e", query, "--", "."]
        + secretPathspecs, at: root)
    } catch ProjectCommandError.commandExited(_, 1) {
      return "\(project)에서 '\(query)'를 찾지 못했습니다."
    }
    let lines = output.split(separator: "\n").map(String.init)
    let shown = lines.prefix(maximumMatches).map { SecretRedactor.redact(String($0.prefix(200))) }
    let more = lines.count > maximumMatches ? "\n… 외 \(lines.count - maximumMatches)곳 더 있습니다. 검색어를 좁혀 주세요." : ""
    return "\(project)에서 '\(query)' 검색 결과 (\(lines.count)곳):\n" + shown.joined(separator: "\n") + more
  }

  static func read(_ file: String, project: String, root: URL) throws -> String {
    let tracked = try ProjectCommandPolicy.run(git, ["ls-files"], at: root).split(separator: "\n").map(String.init)
    let found = matches(for: file, in: tracked)
    // "README" means the top-level one when the name also appears in subfolders.
    let topLevel = found.filter { !$0.contains("/") }
    let candidates = found.count > 1 && topLevel.count == 1 ? topLevel : found
    guard let path = candidates.first else { return "\(project)에서 '\(file)' 파일을 찾지 못했습니다. git이 추적하는 파일만 볼 수 있습니다." }
    guard candidates.count == 1 else {
      return "'\(file)'에 해당하는 파일이 여러 개입니다. 경로로 다시 요청해 주세요:\n" + candidates.prefix(10).joined(separator: "\n")
    }
    guard !isSecretPath(path) else { return "\(path)는 비밀값이 들어 있을 수 있어 보여드리지 않습니다." }
    let url = root.appendingPathComponent(path).standardizedFileURL
    guard url.path.hasPrefix(root.standardizedFileURL.path + "/"),
      let text = try? String(contentsOf: url, encoding: .utf8) else { return "\(path)는 텍스트 파일로 읽을 수 없습니다." }
    let lines = text.components(separatedBy: "\n")
    let body = SecretRedactor.redact(lines.prefix(maximumLines).joined(separator: "\n"))
    let range = lines.count > maximumLines ? " (\(lines.count)줄 중 1-\(maximumLines)줄)" : ""
    return "\(project)/\(path)\(range)\n\(body)"
  }

  /// Exact path first; otherwise a case-insensitive file-name match ("README" finds README.md).
  static func matches(for file: String, in tracked: [String]) -> [String] {
    if tracked.contains(file) { return [file] }
    let wanted = file.lowercased()
    return tracked.filter { path in
      let name = (path as NSString).lastPathComponent.lowercased()
      return path.lowercased().hasSuffix("/" + wanted) || name == wanted || (name as NSString).deletingPathExtension == wanted
    }
  }
}
