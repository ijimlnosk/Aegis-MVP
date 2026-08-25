import AegisWorkerProtocol
import Foundation

enum CodexWorkerRunner {
  static func execute(task: CodingTask, executable: URL, arguments: [String],
                      timeout: TimeInterval) async -> CodingAgentExecution? {
    guard task.mode == .readOnlyAnalysis, let helper = helperURL() else { return nil }
    do {
      let directory = try jobDirectory(), key = artifactKey(task: task)
      let requestURL = directory.appendingPathComponent("\(key).request.json")
      let resultURL = directory.appendingPathComponent("\(key).result.json")
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

  static func recover(sessionId: String, commandId: String) -> DesktopBridgeResult? {
    guard let directory = try? jobDirectory() else { return nil }
    let key = artifactKey(sessionId: sessionId, commandId: commandId)
    let requestURL = directory.appendingPathComponent("\(key).request.json")
    let resultURL = directory.appendingPathComponent("\(key).result.json")
    guard let requestData = try? Data(contentsOf: requestURL),
      let request = try? JSONDecoder().decode(WorkerExecutionRequest.self, from: requestData),
      let resultData = try? Data(contentsOf: resultURL),
      let result = try? JSONDecoder().decode(WorkerExecutionResult.self, from: resultData) else { return nil }
    let parsed = CodexJSONOutputParser.parse(result.stdout,
      projectRoot: URL(fileURLWithPath: request.projectRoot))
    try? FileManager.default.removeItem(at: requestURL); try? FileManager.default.removeItem(at: resultURL)
    let succeeded = result.exitStatus == 0 && !result.timedOut && !parsed.userResult.isEmpty
    return DesktopBridgeResult(status: succeeded ? "completed" : "failed",
      messages: [succeeded ? parsed.userResult : "worker 코드 분석을 완료하지 못했습니다."],
      pendingApproval: nil, failureCode: succeeded ? nil : "workerAnalysisFailed")
  }

  static func hasPendingResult(sessionId: String, commandId: String, now: Date = .now) -> Bool {
    guard let directory = try? jobDirectory() else { return false }
    let key = artifactKey(sessionId: sessionId, commandId: commandId)
    let requestURL = directory.appendingPathComponent("\(key).request.json")
    let resultURL = directory.appendingPathComponent("\(key).result.json")
    guard FileManager.default.fileExists(atPath: requestURL.path),
      !FileManager.default.fileExists(atPath: resultURL.path),
      let values = try? requestURL.resourceValues(forKeys: [.contentModificationDateKey]),
      let modified = values.contentModificationDate else { return false }
    return now.timeIntervalSince(modified) < 920
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
  private static func artifactKey(task: CodingTask) -> String {
    guard let session = task.remoteSessionId, let command = task.remoteCommandId else {
      return task.id.uuidString
    }
    return artifactKey(sessionId: session, commandId: command)
  }
  private static func artifactKey(sessionId: String, commandId: String) -> String {
    let raw = "\(sessionId)--\(commandId)"
    return String(raw.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }.prefix(160))
  }
  private static func cancelled() -> CodingAgentExecution {
    .init(completed: false, userResult: "작업이 취소되었습니다.",
      diagnostics: .init(exitStatus: nil, sandboxMode: "read-only", stderrSummary: nil, eventCount: 1),
      providerEvents: [.failed], timedOut: false, cancelled: true)
  }
}
