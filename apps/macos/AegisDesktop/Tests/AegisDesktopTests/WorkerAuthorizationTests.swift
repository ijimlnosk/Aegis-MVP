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
