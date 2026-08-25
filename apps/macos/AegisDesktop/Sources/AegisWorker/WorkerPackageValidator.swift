import AegisWorkerProtocol
import Darwin
import Foundation

enum WorkerPackageValidator {
  static func run(checks: [String], root: URL) -> [WorkerValidationResult] {
    guard let scripts = scripts(root: root) else {
      return checks.map { .init(check: $0, status: "unsupported", exitCode: nil,
        summary: "package.json 스크립트를 확인할 수 없습니다.") }
    }
    return checks.map { check in
      guard ["typecheck", "lint", "test", "build"].contains(check), scripts.contains(check) else {
        return .init(check: check, status: "unsupported", exitCode: nil,
          summary: "\(check) 스크립트가 없어 건너뜁니다.")
      }
      return execute(check: check, manager: manager(root: root), root: root)
    }
  }

  private static func scripts(root: URL) -> Set<String>? {
    let url = root.appendingPathComponent("package.json")
    guard let data = try? Data(contentsOf: url),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let values = json["scripts"] as? [String: Any] else { return nil }
    return Set(values.keys)
  }

  private static func manager(root: URL) -> String {
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("pnpm-lock.yaml").path) { return "pnpm" }
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("yarn.lock").path) { return "yarn" }
    return "npm"
  }

  private static func execute(check: String, manager: String, root: URL) -> WorkerValidationResult {
    let process = Process(), output = Pipe(), errors = Pipe()
    let fixed = ["/opt/homebrew/bin/\(manager)", "/usr/local/bin/\(manager)", "/usr/bin/\(manager)"]
      .first { FileManager.default.isExecutableFile(atPath: $0) }
    process.executableURL = URL(fileURLWithPath: fixed ?? "/usr/bin/env")
    let command = manager == "yarn" ? [check] : ["run", check]
    process.arguments = fixed == nil ? [manager] + command : command
    process.currentDirectoryURL = root; process.standardOutput = output; process.standardError = errors
    process.environment = environment()
    do { try process.run() } catch {
      return .init(check: check, status: "failed", exitCode: nil, summary: error.localizedDescription)
    }
    let out = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
    let err = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
    let deadline = Date().addingTimeInterval(300)
    while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    if process.isRunning { process.terminate(); Thread.sleep(forTimeInterval: 0.5) }
    if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    let combined = awaitValue(out) + awaitValue(err)
    let summary = String(String(decoding: combined.suffix(2_000), as: UTF8.self).suffix(2_000))
    return .init(check: check, status: process.terminationStatus == 0 ? "passed" : "failed",
      exitCode: process.terminationStatus, summary: summary)
  }

  private static func awaitValue(_ task: Task<Data, Never>) -> Data {
    let semaphore = DispatchSemaphore(value: 0); var value = Data()
    Task { value = await task.value; semaphore.signal() }; semaphore.wait(); return value
  }
  private static func environment() -> [String: String] {
    let source = ProcessInfo.processInfo.environment
    return ["HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "TERM", "CI"].reduce(into: [:]) {
      if let value = source[$1] { $0[$1] = value }
    }.merging(["CI": "1"]) { current, _ in current }
  }
}
