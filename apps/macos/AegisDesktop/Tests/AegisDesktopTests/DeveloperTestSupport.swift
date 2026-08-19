import Foundation
@testable import AegisDesktop

enum DeveloperTestSupport {
  static func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @discardableResult static func process(_ executable: String, _ arguments: [String], at url: URL) throws -> String {
    let process = Process(); let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
    process.currentDirectoryURL = url; process.standardOutput = pipe; process.standardError = pipe
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ProjectCommandError.commandFailed("test setup failed") }
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  }

  static func gitProject() throws -> URL {
    let url = try directory()
    try process("/usr/bin/git", ["init", "-b", "main"], at: url)
    try "initial\n".write(to: url.appending(path: "README.md"), atomically: true, encoding: .utf8)
    try process("/usr/bin/git", ["add", "README.md"], at: url)
    try process("/usr/bin/git", ["-c", "user.name=Aegis", "-c", "user.email=aegis@example.test", "commit", "-m", "initial"], at: url)
    return url
  }

  static func repositories(project: URL) throws -> (MemoryRepository, DevelopmentSessionRepository) {
    let database = try directory().appending(path: "test.sqlite")
    let memory = MemoryRepository(databaseURL: database); try memory.bootstrap()
    _ = try memory.save(MemoryRecord(type: .project, key: "PTFriends", value: project.path))
    let sessions = DevelopmentSessionRepository(databaseURL: database); try sessions.bootstrap()
    return (memory, sessions)
  }
}
