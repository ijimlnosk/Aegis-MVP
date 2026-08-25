import Foundation

public struct WorkerExecutionRequest: Codable, Sendable {
  public let executable: String
  public let projectRoot: String
  public let arguments: [String]
  public let timeout: TimeInterval

  public init(executable: String, projectRoot: String, arguments: [String], timeout: TimeInterval) {
    self.executable = executable; self.projectRoot = projectRoot
    self.arguments = arguments; self.timeout = timeout
  }

  public var isSafeReadOnlyCodex: Bool {
    let allowedExecutable = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"]
      .contains(executable)
    guard allowedExecutable, FileManager.default.fileExists(atPath: projectRoot),
      let sandbox = arguments.firstIndex(of: "--sandbox"), arguments.indices.contains(sandbox + 1),
      arguments[sandbox + 1] == "read-only" else { return false }
    return !arguments.contains("workspace-write") && !arguments.contains("danger-full-access")
  }
}

public struct WorkerExecutionResult: Codable, Sendable {
  public let exitStatus: Int32
  public let stdout: Data
  public let hadStderr: Bool
  public let timedOut: Bool

  public init(exitStatus: Int32, stdout: Data, hadStderr: Bool, timedOut: Bool) {
    self.exitStatus = exitStatus; self.stdout = stdout
    self.hadStderr = hadStderr; self.timedOut = timedOut
  }
}
