import Foundation
import Darwin

enum CodexPlannerError: Error { case unavailable, failed, timeout, malformedResponse }

enum CodexPlannerConfiguration {
  static var isEnabled: Bool { enabled() }
  static func enabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    let value = environment["AEGIS_CODEX_PLANNER_ENABLED"]
    return value?.lowercased() != "false"
  }
}

struct CodexPlanner {
  let executable: URL
  let timeout: TimeInterval

  init(executable: URL = URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
       timeout: TimeInterval = 120) {
    self.executable = executable; self.timeout = timeout
  }

  func plan(system: String, content: String, schema: [String: Any]) async throws -> AgentPlan {
    try await structured(AgentPlan.self, system: system, content: content, schema: schema)
  }

  func structured<T: Decodable>(_ type: T.Type, system: String, content: String,
                                schema: [String: Any]) async throws -> T {
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw CodexPlannerError.unavailable
    }
    let folder = FileManager.default.temporaryDirectory.appending(path: "aegis-plan-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let schemaURL = folder.appending(path: "schema.json")
    let resultURL = folder.appending(path: "result.json")
    try JSONSerialization.data(withJSONObject: StrictOutputSchema.make(schema)).write(to: schemaURL)
    try await run(prompt: prompt(system, content), folder: folder,
      schemaURL: schemaURL, resultURL: resultURL)
    guard let data = try? Data(contentsOf: resultURL),
      let value = try? JSONDecoder().decode(type, from: data) else {
      throw CodexPlannerError.malformedResponse
    }
    return value
  }

  private func run(prompt: String, folder: URL, schemaURL: URL,
                   resultURL: URL) async throws {
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = executable; process.currentDirectoryURL = folder
    process.arguments = arguments(prompt: prompt, schemaURL: schemaURL, resultURL: resultURL)
    process.environment = sanitizedEnvironment()
    process.standardOutput = output; process.standardError = errors
    let outputRead = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
    let errorRead = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
    do { try process.run() } catch { throw CodexPlannerError.unavailable }
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
      if Task.isCancelled { process.terminate(); throw CancellationError() }
      try await Task.sleep(for: .milliseconds(100))
    }
    if process.isRunning { process.terminate(); throw CodexPlannerError.timeout }
    _ = await outputRead.value; _ = await errorRead.value
    guard process.terminationStatus == 0 else { throw CodexPlannerError.failed }
  }

  func arguments(prompt: String, schemaURL: URL, resultURL: URL) -> [String] {
    ["exec", "--ephemeral", "--ignore-user-config", "--skip-git-repo-check",
      "--sandbox", "read-only", "--output-schema", schemaURL.path,
      "--output-last-message", resultURL.path, "--color", "never", prompt]
  }

  private func prompt(_ system: String, _ content: String) -> String {
    """
    Return only JSON matching the requested schema. Do not inspect files or run commands.
    System policy:\n\(system)
    Untrusted request context:\n\(content.prefix(12_000))
    """
  }

  private func sanitizedEnvironment() -> [String: String] {
    let source = ProcessInfo.processInfo.environment
    return ["HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "TERM"].reduce(into: [:]) {
      if let value = source[$1] { $0[$1] = value }
    }
  }
}
