import AegisWorkerProtocol
import Darwin
import Foundation

enum WorkerReadOnlyExecutor {
  static func run(requestURL: URL, resultURL: URL) throws {
    let request = try JSONDecoder().decode(WorkerExecutionRequest.self,
      from: Data(contentsOf: requestURL))
    guard request.isSafeReadOnlyCodex else { throw WorkerError.unsafeRequest }
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: request.executable)
    process.currentDirectoryURL = URL(fileURLWithPath: request.projectRoot)
    process.arguments = request.arguments
    process.environment = environment()
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let outputRead = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
    let errorRead = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }
    let deadline = Date().addingTimeInterval(min(max(request.timeout, 10), 900))
    while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    let timedOut = process.isRunning
    if timedOut { process.terminate(); Thread.sleep(forTimeInterval: 0.5) }
    if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    let stdout = awaitValue(outputRead), stderr = awaitValue(errorRead)
    let result = WorkerExecutionResult(exitStatus: timedOut ? -1 : process.terminationStatus,
      stdout: Data(stdout.prefix(2_000_000)), hadStderr: !stderr.isEmpty, timedOut: timedOut)
    try JSONEncoder().encode(result).write(to: resultURL, options: .atomic)
  }

  private static func awaitValue(_ task: Task<Data, Never>) -> Data {
    let semaphore = DispatchSemaphore(value: 0)
    var value = Data()
    Task { value = await task.value; semaphore.signal() }
    semaphore.wait()
    return value
  }

  private static func environment() -> [String: String] {
    let source = ProcessInfo.processInfo.environment
    return ["HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "TERM"].reduce(into: [:]) {
      if let value = source[$1] { $0[$1] = value }
    }
  }
  private enum WorkerError: Error { case unsafeRequest }
}
