import Foundation

enum GitWorkingTreeKind: String, Codable, Sendable { case modified, added, deleted, renamed, copied, untracked, conflicted }

struct GitWorkingTreeEntry: Codable, Sendable, Equatable {
  let path: String; let originalPath: String?
  let indexStatus: String; let workTreeStatus: String
  let kind: GitWorkingTreeKind; let contentFingerprint: String
}

struct GitNameStatusEntry: Codable, Sendable, Equatable {
  let status: String; let path: String; let originalPath: String?
}

struct GitWorkingTreeSnapshot: Codable, Sendable, Equatable {
  let head: String; let branch: String; let entries: [GitWorkingTreeEntry]
  let unstagedChanges: [GitNameStatusEntry]; let stagedChanges: [GitNameStatusEntry]
  let trackedFiles: [String]
  var changedFiles: [String] { entries.map(\.path).sorted() }
  var isDirty: Bool { !entries.isEmpty }
}

struct GitWorkingTreeDelta: Codable, Sendable, Equatable {
  let addedEntries: [GitWorkingTreeEntry]; let removedEntries: [GitWorkingTreeEntry]
  let changedEntries: [GitWorkingTreeEntry]; let headChanged: Bool; let branchChanged: Bool
  var hasChanges: Bool { headChanged || branchChanged || !addedEntries.isEmpty || !removedEntries.isEmpty || !changedEntries.isEmpty }
  var observedPaths: [String] {
    Array(Set((addedEntries + removedEntries + changedEntries)
      .flatMap { [$0.path, $0.originalPath].compactMap { $0 } })).sorted()
  }
  static let empty = Self(addedEntries: [], removedEntries: [], changedEntries: [],
    headChanged: false, branchChanged: false)
}

typealias CodingTaskSnapshot = GitWorkingTreeSnapshot

struct CodingTaskDiff: Codable, Sendable, Equatable {
  let attributableFiles: [String]; let preexistingFiles: [String]
  let overlappingFiles: [String]; let diffStat: String
  var rollbackFiles: [String] = []; var workingTreeDelta: GitWorkingTreeDelta = .empty
  var rollbackIsolated: Bool { overlappingFiles.isEmpty && !attributableFiles.isEmpty && rollbackFiles == attributableFiles }
}

enum CodingGitInspector {
  static func snapshot(at root: URL) throws -> GitWorkingTreeSnapshot {
    let head = string(try runGit(["rev-parse", "HEAD"], at: root))
    let branch = string(try runGit(["branch", "--show-current"], at: root))
    let status = try runGit(["status", "--porcelain=v1", "-z", "--untracked-files=all"], at: root)
    let unstaged = try runGit(["diff", "--name-status", "-z"], at: root)
    let staged = try runGit(["diff", "--cached", "--name-status", "-z"], at: root)
    let tracked = split(try runGit(["ls-files", "-z"], at: root)).map(string).sorted()
    let entries = GitPorcelainParser.parse(status).map { entry in
      GitWorkingTreeEntry(path: entry.path, originalPath: entry.originalPath,
        indexStatus: entry.indexStatus, workTreeStatus: entry.workTreeStatus,
        kind: entry.kind, contentFingerprint: fingerprint(entry, at: root))
    }.sorted { $0.path < $1.path }
    return .init(head: head, branch: branch, entries: entries,
      unstagedChanges: GitNameStatusParser.parse(unstaged),
      stagedChanges: GitNameStatusParser.parse(staged), trackedFiles: tracked)
  }

  static func delta(before: GitWorkingTreeSnapshot, after: GitWorkingTreeSnapshot) -> GitWorkingTreeDelta {
    let old = Dictionary(uniqueKeysWithValues: before.entries.map { ($0.path, $0) })
    let new = Dictionary(uniqueKeysWithValues: after.entries.map { ($0.path, $0) })
    let added = new.keys.filter { old[$0] == nil }.compactMap { new[$0] }.sorted { $0.path < $1.path }
    let removed = old.keys.filter { new[$0] == nil }.compactMap { old[$0] }.sorted { $0.path < $1.path }
    let changed = new.keys.filter { old[$0] != nil && old[$0] != new[$0] }
      .compactMap { new[$0] }.sorted { $0.path < $1.path }
    return .init(addedEntries: added, removedEntries: removed, changedEntries: changed,
      headChanged: before.head != after.head, branchChanged: before.branch != after.branch)
  }

  static func diff(before: GitWorkingTreeSnapshot, after: GitWorkingTreeSnapshot,
                   at root: URL) throws -> CodingTaskDiff {
    let delta = delta(before: before, after: after), beforePaths = Set(before.changedFiles)
    let paths = delta.observedPaths
    return .init(attributableFiles: paths, preexistingFiles: before.changedFiles,
      overlappingFiles: paths.filter(beforePaths.contains),
      diffStat: string(try runGit(["diff", "--stat"], at: root)),
      rollbackFiles: paths.filter(Set(before.trackedFiles).contains), workingTreeDelta: delta)
  }

  private static func fingerprint(_ entry: GitWorkingTreeEntry, at root: URL) -> String {
    (try? string(runGit(["hash-object", "--", entry.path], at: root))) ?? "missing"
  }

  private static func runGit(_ arguments: [String], at root: URL) throws -> Data {
    let outputURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let errorURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: outputURL); try? FileManager.default.removeItem(at: errorURL) }
    let output = try FileHandle(forWritingTo: outputURL), error = try FileHandle(forWritingTo: errorURL)
    defer { try? output.close(); try? error.close() }
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments; process.currentDirectoryURL = root
    process.standardOutput = output; process.standardError = error
    do { try process.run(); process.waitUntilExit() }
    catch { throw ProjectCommandError.infrastructureFailure(error.localizedDescription) }
    guard process.terminationStatus == 0 else {
      let detail = (try? Data(contentsOf: errorURL)).map(string) ?? "Git snapshot failed."
      throw ProjectCommandError.commandFailed(detail)
    }
    return try Data(contentsOf: outputURL)
  }

  static func split(_ data: Data) -> [Data] {
    [UInt8](data).split(separator: UInt8(0)).map { Data($0) }
  }
  static func string(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
  }
}
