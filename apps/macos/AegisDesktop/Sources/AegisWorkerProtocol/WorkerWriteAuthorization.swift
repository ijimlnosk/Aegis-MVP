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
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
