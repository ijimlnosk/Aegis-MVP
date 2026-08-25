import AegisWorkerProtocol
import Foundation
import Testing

@Test func workerWriteAuthorizationIsScopedExpiringAndSingleUse() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let now = Date(), store = try WorkerAuthorizationStore(databaseURL: root.appendingPathComponent("db.sqlite"))
  let value = WorkerWriteAuthorization(commandId: "C1", sessionId: "S1", approvalId: UUID(),
    request: "fix lint", projectRoot: "/trusted/project", baselineHead: "abc",
    baselineBranch: "feature", baselineChanges: [], maximumChangedFiles: 20,
    requiredValidations: ["lint", "test"], approvedAt: now, lifetime: 60)
  try store.issue(value)

  #expect(try store.consume(commandId: "C1", sessionId: "S1", request: "wrong",
    projectRoot: "/trusted/project", now: now) == nil)
  #expect(try store.consume(commandId: "C1", sessionId: "S1", request: "fix lint",
    projectRoot: "/trusted/project", now: now) == value)
  #expect(try store.consume(commandId: "C1", sessionId: "S1", request: "fix lint",
    projectRoot: "/trusted/project", now: now) == nil)
}

@Test func workerWriteGuardRejectsChangedBaseline() {
  let now = Date(), entry = WorkerBaselineEntry(path: "src/a.ts", fingerprint: "one")
  let authorization = WorkerWriteAuthorization(commandId: "C1", sessionId: "S1",
    approvalId: UUID(), request: "fix", projectRoot: "/trusted", baselineHead: "abc",
    baselineBranch: "feature", baselineChanges: [entry], maximumChangedFiles: 20,
    requiredValidations: ["lint"], approvedAt: now)
  let exact = WorkerGitBaseline(head: "abc", branch: "feature", changes: [entry])
  let changed = WorkerGitBaseline(head: "abc", branch: "other", changes: [entry])

  #expect(WorkerWriteGuard.allows(authorization, commandId: "C1", sessionId: "S1",
    request: "fix", projectRoot: "/trusted", current: exact, now: now))
  #expect(!WorkerWriteGuard.allows(authorization, commandId: "C1", sessionId: "S1",
    request: "fix", projectRoot: "/trusted", current: changed, now: now))
}
