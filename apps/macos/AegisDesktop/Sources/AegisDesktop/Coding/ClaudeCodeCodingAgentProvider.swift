import Darwin
import Foundation

struct ClaudeCodeCodingAgentProvider: CodingAgentProvider {
  let executable: URL
  var name: String { "Claude Code" }
  var identifier: CodingAgentProviderID { .claude }
  var executablePath: String { executable.path }

  init(executable: URL? = nil,
       environment: [String: String] = ProcessInfo.processInfo.environment) {
    self.executable = executable ?? Self.installedExecutable(environment)
  }

  func isAvailable() -> Bool {
    FileManager.default.isExecutableFile(atPath: executable.path) && version() != nil
  }

  func version() -> String? { ProviderVersionProbe.read(executable: executable) }

  func arguments(for task: CodingTask, policy: CodingExecutionPolicy? = nil) -> [String] {
    let canWrite = (policy ?? .policy(for: task.mode)).allowWrites && task.mode == .workspaceWrite
    let tools = canWrite ? "Read,Glob,Grep,Edit,Write" : "Read,Glob,Grep"
    return ["--print", "--output-format", "json", "--no-session-persistence",
      "--safe-mode", "--disable-slash-commands", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
      "--permission-mode", canWrite ? "acceptEdits" : "plan", "--tools=\(tools)",
      CodingPrompt.make(task)]
  }

  func execute(_ task: CodingTask, policy: CodingExecutionPolicy,
               timeout: TimeInterval) async -> CodingAgentExecution {
    guard isAvailable() else { return failure("Claude Code 실행 파일을 찾거나 검증하지 못했습니다.") }
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = executable; process.currentDirectoryURL = task.projectRoot
    process.arguments = arguments(for: task, policy: policy)
    process.environment = sanitizedEnvironment()
    process.standardOutput = output; process.standardError = errors
    do { try process.run() } catch { return failure(error.localizedDescription) }
    return await wait(process, output: output, errors: errors, timeout: timeout,
      sandbox: task.mode == .readOnlyAnalysis ? "plan/read-only-tools" : "acceptEdits/workspace-write")
  }

  private func wait(_ process: Process, output: Pipe, errors: Pipe, timeout: TimeInterval,
                    sandbox: String) async -> CodingAgentExecution {
    let read = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
    let errorRead = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
      if Task.isCancelled {
        await stop(process); _ = await read.value; _ = await errorRead.value
        return failure("작업이 취소되었습니다.", cancelled: true)
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
    if process.isRunning {
      await stop(process); _ = await read.value; _ = await errorRead.value
      return failure("코딩 작업 시간이 초과되었습니다.", timedOut: true)
    }
    let result = ClaudeCodeOutputParser.userResult(from: await read.value,
      projectRoot: process.currentDirectoryURL ?? URL(fileURLWithPath: "/"))
    let stderr = await errorRead.value
    return .init(completed: process.terminationStatus == 0 && !result.isEmpty, userResult: result,
      diagnostics: .init(exitStatus: process.terminationStatus, sandboxMode: sandbox,
        stderrSummary: stderr.isEmpty ? nil : "provider stderr available", eventCount: 2),
      providerEvents: [.started, .resultReceived, process.terminationStatus == 0 ? .completed : .failed],
      timedOut: false, cancelled: false)
  }

  private func stop(_ process: Process) async {
    process.terminate()
    for _ in 0..<5 where process.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
    if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
  }

  private func failure(_ message: String, timedOut: Bool = false,
                       cancelled: Bool = false) -> CodingAgentExecution {
    .init(completed: false, userResult: message,
      diagnostics: .init(exitStatus: nil, sandboxMode: "unknown", stderrSummary: nil, eventCount: 1),
      providerEvents: [.failed], timedOut: timedOut, cancelled: cancelled)
  }

  private func sanitizedEnvironment() -> [String: String] {
    let source = ProcessInfo.processInfo.environment
    let allowed = ["HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "TERM", "ANTHROPIC_API_KEY"]
    return allowed.reduce(into: [:]) { if let value = source[$1] { $0[$1] = value } }
  }

  private static func installedExecutable(_ environment: [String: String]) -> URL {
    let candidates = [environment["AEGIS_CLAUDE_CODE_PATH"], "/opt/homebrew/bin/claude",
      "/usr/local/bin/claude"].compactMap { $0 }.map(URL.init(fileURLWithPath:))
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
      ?? URL(fileURLWithPath: "/opt/homebrew/bin/claude")
  }
}
