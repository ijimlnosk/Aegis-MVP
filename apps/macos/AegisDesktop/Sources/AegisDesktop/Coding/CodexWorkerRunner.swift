import AegisWorkerProtocol
import Foundation

enum CodexWorkerRunner {
  static func execute(task: CodingTask, executable: URL, arguments: [String],
                      timeout: TimeInterval) async -> CodingAgentExecution? {
    guard task.mode == .readOnlyAnalysis, let helper = helperURL() else { return nil }
    do {
      let directory = try jobDirectory(), requestURL = directory.appendingPathComponent("\(task.id).request.json")
      let resultURL = directory.appendingPathComponent("\(task.id).result.json")
      let request = WorkerExecutionRequest(executable: executable.path,
        projectRoot: task.projectRoot.path, arguments: arguments, timeout: timeout)
      try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
      let process = Process()
      process.executableURL = helper
      process.arguments = ["--execute-read-only", requestURL.path, resultURL.path]
      process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
      try process.run()
      let deadline = Date().addingTimeInterval(timeout + 10)
      while !FileManager.default.fileExists(atPath: resultURL.path), Date() < deadline {
        if Task.isCancelled { return cancelled() }
        try? await Task.sleep(for: .milliseconds(100))
      }
      guard let data = try? Data(contentsOf: resultURL),
        let result = try? JSONDecoder().decode(WorkerExecutionResult.self, from: data) else { return nil }
      try? FileManager.default.removeItem(at: requestURL); try? FileManager.default.removeItem(at: resultURL)
      let parsed = CodexJSONOutputParser.parse(result.stdout, projectRoot: task.projectRoot)
      return .init(completed: result.exitStatus == 0 && !result.timedOut,
        userResult: parsed.userResult,
        diagnostics: .init(exitStatus: result.exitStatus, sandboxMode: "read-only",
          stderrSummary: result.hadStderr ? "provider stderr available" : nil,
          eventCount: parsed.events.count), providerEvents: parsed.events,
        timedOut: result.timedOut, cancelled: false)
    } catch { return nil }
  }

  private static func helperURL() -> URL? {
    let value = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AegisWorker")
    return FileManager.default.isExecutableFile(atPath: value.path) ? value : nil
  }
  private static func jobDirectory() throws -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Aegis/worker-jobs", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
  private static func cancelled() -> CodingAgentExecution {
    .init(completed: false, userResult: "작업이 취소되었습니다.",
      diagnostics: .init(exitStatus: nil, sandboxMode: "read-only", stderrSummary: nil, eventCount: 1),
      providerEvents: [.failed], timedOut: false, cancelled: true)
  }
}
