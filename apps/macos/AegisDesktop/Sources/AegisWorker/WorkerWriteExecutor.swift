import AegisWorkerProtocol
import Darwin
import Foundation

enum WorkerWriteExecutor {
  static func run(requestURL: URL, resultURL: URL) throws {
    let request = try JSONDecoder().decode(WorkerExecutionRequest.self,
      from: Data(contentsOf: requestURL))
    guard request.isSafeWorkspaceWriteCodex, let database = request.databasePath,
      let command = request.commandId, let session = request.sessionId,
      let approvedRequest = request.authorizationRequest else { throw WriteError.unsafeRequest }
    let root = URL(fileURLWithPath: request.projectRoot)
    let authorizations = try WorkerAuthorizationStore(databaseURL: URL(fileURLWithPath: database))
    guard let authorization = try authorizations.consume(commandId: command, sessionId: session,
      request: approvedRequest, projectRoot: request.projectRoot) else { throw WriteError.notApproved }
    let before = try WorkerGitBaselineReader.read(root: root)
    guard WorkerWriteGuard.allows(authorization, commandId: command, sessionId: session,
      request: approvedRequest, projectRoot: request.projectRoot, current: before) else {
      throw WriteError.staleBaseline
    }
    let execution = try execute(request, root: root)
    let after = try WorkerGitBaselineReader.read(root: root)
    let changed = WorkerWriteGuard.changedFiles(from: before, to: after)
    let existing = Set(before.changes.map(\.path))
    let overlaps = changed.filter(existing.contains)
    let safe = execution.exitStatus == 0 && !execution.timedOut
      && changed.count <= authorization.maximumChangedFiles && overlaps.isEmpty
      && before.head == after.head && before.branch == after.branch
    let result = WorkerExecutionResult(exitStatus: execution.exitStatus, stdout: execution.stdout,
      hadStderr: execution.hadStderr, timedOut: execution.timedOut,
      changedFiles: changed, overlappingFiles: overlaps, writeSafetyPassed: safe)
    try JSONEncoder().encode(result).write(to: resultURL, options: .atomic)
  }

  private static func execute(_ request: WorkerExecutionRequest,
                              root: URL) throws -> WorkerExecutionResult {
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: request.executable)
    process.currentDirectoryURL = root; process.arguments = request.arguments
    process.environment = environment(); process.standardOutput = output; process.standardError = errors
    try process.run()
    let out = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
    let err = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
    let deadline = Date().addingTimeInterval(min(max(request.timeout, 30), 900))
    while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    let timedOut = process.isRunning
    if timedOut { process.terminate(); Thread.sleep(forTimeInterval: 0.5) }
    if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    let stdout = awaitValue(out), stderr = awaitValue(err)
    return WorkerExecutionResult(exitStatus: timedOut ? -1 : process.terminationStatus,
      stdout: Data(stdout.prefix(2_000_000)), hadStderr: !stderr.isEmpty, timedOut: timedOut)
  }

  private static func awaitValue(_ task: Task<Data, Never>) -> Data {
    let semaphore = DispatchSemaphore(value: 0); var value = Data()
    Task { value = await task.value; semaphore.signal() }; semaphore.wait(); return value
  }
  private static func environment() -> [String: String] {
    let source = ProcessInfo.processInfo.environment
    return ["HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "TERM"].reduce(into: [:]) {
      if let value = source[$1] { $0[$1] = value }
    }
  }
  private enum WriteError: Error { case unsafeRequest, notApproved, staleBaseline }
}
