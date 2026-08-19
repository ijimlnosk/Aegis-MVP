import Foundation

enum ProjectCommandError: LocalizedError {
  case unknownProject(String), invalidProjectPath(String), unsupportedScript(String)
  case missingPackageJSON, invalidPackageJSON, commandFailed(String), infrastructureFailure(String)

  var errorDescription: String? {
    switch self {
    case .unknownProject(let value): "등록된 프로젝트를 찾지 못했습니다: \(value)"
    case .invalidProjectPath(let value): "프로젝트 경로가 유효한 디렉터리가 아닙니다: \(value)"
    case .unsupportedScript(let value): "package.json에 지원되는 \(value) 스크립트가 없습니다."
    case .missingPackageJSON: "package.json을 찾지 못했습니다."
    case .invalidPackageJSON: "package.json을 읽을 수 없습니다."
    case .commandFailed(let value): value
    case .infrastructureFailure(let value): value
    }
  }
}

enum ProjectCommandPolicy {
  static let maximumCommits = 10
  static let maximumChangedFiles = 50
  static let maximumOutputBytes = 64_000

  static func projectURL(_ name: String, repository: MemoryRepository) throws -> URL {
    guard let project = ProjectEntityResolver.resolve(name: name, repository: repository) else {
      throw ProjectCommandError.unknownProject(name)
    }
    guard let path = project.path, path.hasPrefix("/") else {
      throw ProjectCommandError.invalidProjectPath(project.path ?? "")
    }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
      throw ProjectCommandError.invalidProjectPath(path)
    }
    return url
  }

  static func run(_ executable: String, _ arguments: [String], at directory: URL) throws -> String {
    let process = Process(); let output = Pipe(); let error = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments; process.currentDirectoryURL = directory
    process.standardOutput = output; process.standardError = error
    do { try process.run() } catch {
      throw ProjectCommandError.infrastructureFailure(error.localizedDescription)
    }
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    let text = String(decoding: data.prefix(maximumOutputBytes), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    if [126, 127].contains(process.terminationStatus) {
      let detail = String(decoding: errorData.prefix(maximumOutputBytes), as: UTF8.self)
      throw ProjectCommandError.infrastructureFailure(detail.isEmpty ? "실행 도구를 찾지 못했습니다." : detail)
    }
    if process.terminationStatus != 0 {
      let detail = String(decoding: errorData.prefix(maximumOutputBytes), as: UTF8.self)
      throw ProjectCommandError.commandFailed(detail.isEmpty ? "도구 실행에 실패했습니다." : detail)
    }
    return text
  }
}
