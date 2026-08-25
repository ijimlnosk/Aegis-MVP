import AegisWorkerProtocol
import Foundation
import Testing

@Test func workerLeasePreventsDuplicateClaimsAndAllowsExpiredRecovery() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try WorkerLeaseStore(databaseURL: root.appendingPathComponent("jobs.sqlite"))
  let contract = WorkerJobContract(commandId: "C1", sessionId: "S1", state: .queued,
    risk: .readOnly, approvalGranted: false, hasValidationPlan: false, leaseExpiresAt: nil)
  try store.upsert(contract)
  let now = Date()

  #expect(try store.claim(commandId: "C1", sessionId: "S1", owner: "W1", now: now))
  #expect(try !store.claim(commandId: "C1", sessionId: "S1", owner: "W2", now: now))
  #expect(try store.heartbeat(commandId: "C1", sessionId: "S1", owner: "W1", now: now))
  #expect(try store.claim(commandId: "C1", sessionId: "S1", owner: "W2",
    now: now.addingTimeInterval(31)))
}
