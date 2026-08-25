import CryptoKit
import Foundation

public struct WorkerBaselineEntry: Codable, Sendable, Equatable {
  public let path: String
  public let fingerprint: String
  public init(path: String, fingerprint: String) {
    self.path = path; self.fingerprint = fingerprint
  }
}

public struct WorkerWriteAuthorization: Codable, Sendable, Equatable {
  public let commandId: String
  public let sessionId: String
  public let approvalId: UUID
  public let requestDigest: String
  public let projectRoot: String
  public let baselineHead: String
  public let baselineBranch: String
  public let baselineChanges: [WorkerBaselineEntry]
  public let maximumChangedFiles: Int
  public let requiredValidations: [String]
  public let approvedAt: Date
  public let expiresAt: Date

  public init(commandId: String, sessionId: String, approvalId: UUID, request: String,
              projectRoot: String, baselineHead: String, baselineBranch: String,
              baselineChanges: [WorkerBaselineEntry], maximumChangedFiles: Int,
              requiredValidations: [String], approvedAt: Date = .now,
              lifetime: TimeInterval = 30 * 60) {
    self.commandId = commandId; self.sessionId = sessionId; self.approvalId = approvalId
    requestDigest = Self.digest(request); self.projectRoot = projectRoot
    self.baselineHead = baselineHead; self.baselineBranch = baselineBranch
    self.baselineChanges = baselineChanges.sorted { $0.path < $1.path }
    self.maximumChangedFiles = maximumChangedFiles
    self.requiredValidations = requiredValidations.sorted()
    self.approvedAt = approvedAt; expiresAt = approvedAt.addingTimeInterval(lifetime)
  }

  public func authorizes(commandId: String, sessionId: String, request: String,
                         projectRoot: String, now: Date = .now) -> Bool {
    self.commandId == commandId && self.sessionId == sessionId
      && self.projectRoot == projectRoot && requestDigest == Self.digest(request)
      && now >= approvedAt && now < expiresAt
  }

  public static func digest(_ value: String) -> String {
    digest(Data(value.utf8))
  }

  public static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

public struct WorkerGitBaseline: Codable, Sendable, Equatable {
  public let head: String
  public let branch: String
  public let changes: [WorkerBaselineEntry]

  public init(head: String, branch: String, changes: [WorkerBaselineEntry]) {
    self.head = head; self.branch = branch
    self.changes = changes.sorted { $0.path < $1.path }
  }
}

public enum WorkerWriteGuard {
  public static func allows(_ authorization: WorkerWriteAuthorization,
                            commandId: String, sessionId: String, request: String,
                            projectRoot: String, current: WorkerGitBaseline,
                            now: Date = .now) -> Bool {
    authorization.authorizes(commandId: commandId, sessionId: sessionId,
      request: request, projectRoot: projectRoot, now: now)
      && authorization.baselineHead == current.head
      && authorization.baselineBranch == current.branch
      && authorization.baselineChanges == current.changes
      && (1...100).contains(authorization.maximumChangedFiles)
      && !authorization.requiredValidations.isEmpty
  }

  public static func changedFiles(from baseline: WorkerGitBaseline,
                                  to current: WorkerGitBaseline) -> [String] {
    let before = Dictionary(uniqueKeysWithValues: baseline.changes.map { ($0.path, $0.fingerprint) })
    let after = Dictionary(uniqueKeysWithValues: current.changes.map { ($0.path, $0.fingerprint) })
    return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.sorted()
  }
}
