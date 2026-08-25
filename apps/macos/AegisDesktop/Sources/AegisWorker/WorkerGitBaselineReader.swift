import AegisWorkerProtocol
import Foundation

enum WorkerGitBaselineReader {
  static func read(root: URL) throws -> WorkerGitBaseline {
    let head = try text(git(["rev-parse", "HEAD"], root: root))
    let branch = try text(git(["branch", "--show-current"], root: root))
    let status = try git(["status", "--porcelain=v1", "-z", "--untracked-files=all"], root: root)
    let paths = try statusPaths(status)
    let changes = paths.map { path in
      let file = root.appendingPathComponent(path)
      let data = (try? Data(contentsOf: file)) ?? Data("missing".utf8)
      let fingerprint = WorkerWriteAuthorization.digest(data)
      return WorkerBaselineEntry(path: path, fingerprint: fingerprint)
    }
    return WorkerGitBaseline(head: head, branch: branch, changes: changes)
  }

  static func statusPaths(_ data: Data) throws -> [String] {
    let records = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    var paths: [String] = [], index = 0
    while index < records.count {
      let record = records[index]
      guard record.count >= 4 else { throw ReaderError.malformedStatus }
      let status = String(record.prefix(2)), path = String(record.dropFirst(3))
      if status.contains("R") || status.contains("C") {
        guard records.indices.contains(index + 1) else { throw ReaderError.malformedStatus }
        paths.append(records[index + 1]); index += 2
      } else { paths.append(path); index += 1 }
    }
    return Array(Set(paths)).sorted()
  }

  private static func git(_ arguments: [String], root: URL) throws -> Data {
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments; process.currentDirectoryURL = root
    process.standardOutput = output; process.standardError = FileHandle.nullDevice
    try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ReaderError.gitFailed }
    return data
  }
  private static func text(_ data: Data) throws -> String {
    let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { throw ReaderError.gitFailed }; return value
  }
  private enum ReaderError: Error { case gitFailed, malformedStatus }
}
