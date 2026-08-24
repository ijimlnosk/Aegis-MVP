import Foundation

enum ProjectPackageManager: String, Codable { case npm, pnpm, yarn }

struct ProjectPackage: Equatable {
  let manager: ProjectPackageManager
  let scripts: [String]
}

enum PackageScriptTool {
  static let supported = ["typecheck", "test", "lint", "build"]

  static func inspect(at project: URL) throws -> ProjectPackage {
    let packageURL = project.appending(path: "package.json")
    guard FileManager.default.fileExists(atPath: packageURL.path) else { throw ProjectCommandError.missingPackageJSON }
    guard let data = try? Data(contentsOf: packageURL),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let scripts = json["scripts"] as? [String: Any] else { throw ProjectCommandError.invalidPackageJSON }
    return ProjectPackage(manager: manager(at: project), scripts: scripts.keys.sorted())
  }

  static func manager(at project: URL) -> ProjectPackageManager {
    let manager: [(String, ProjectPackageManager)] = [("package-lock.json", .npm),
      ("pnpm-lock.yaml", .pnpm), ("yarn.lock", .yarn)]
    return manager.first { FileManager.default.fileExists(atPath: project.appending(path: $0.0).path) }?.1 ?? .npm
  }

  static func run(_ script: String, at project: URL) throws -> String {
    guard supported.contains(script) else { throw ProjectCommandError.unsupportedScript(script) }
    let package = try inspect(at: project)
    guard package.scripts.contains(script) else { throw ProjectCommandError.unsupportedScript(script) }
    let tool = package.manager.rawValue
    let toolArguments = package.manager == .yarn ? [script] : ["run", script]
    let (executable, arguments) = resolveExecutable(tool, arguments: toolArguments)
    return try ProjectCommandPolicy.run(executable, arguments, at: project)
  }

  private static func resolveExecutable(_ tool: String, arguments: [String]) -> (String, [String]) {
    let candidates = ["/opt/homebrew/bin/\(tool)", "/usr/local/bin/\(tool)", "/usr/bin/\(tool)"]
    if let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
      return (executable, arguments)
    }
    return ("/usr/bin/env", [tool] + arguments)
  }
}
