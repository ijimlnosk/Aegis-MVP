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
    let executable = "/usr/bin/env"
    let arguments = package.manager == .yarn ? ["yarn", script] : [package.manager.rawValue, "run", script]
    return try ProjectCommandPolicy.run(executable, arguments, at: project)
  }
}
