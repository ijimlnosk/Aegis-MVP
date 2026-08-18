import Foundation

enum MemoryProjectTool {
  static func status(project: String, repository: MemoryRepository) throws -> String {
    guard let memory = try repository.find(type: .project, key: project) else {
      throw MemoryProjectError.unknownProject(project)
    }
    let path = URL(fileURLWithPath: memory.value).standardizedFileURL
    guard memory.value.hasPrefix("/"), FileManager.default.fileExists(atPath: path.path) else {
      throw MemoryProjectError.invalidPath(memory.value)
    }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["status", "--short", "--branch"]
    process.currentDirectoryURL = path
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard process.terminationStatus == 0 else { throw MemoryProjectError.git(text) }
    return text.isEmpty ? "변경 사항 없음" : text
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
