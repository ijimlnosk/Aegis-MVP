import AegisWorkerProtocol
import Foundation
import Testing

@Test func workerRecoveryPolicyFailsClosedForUnapprovedMutation() {
  let job = WorkerJobContract(commandId: "C1", sessionId: "S1", state: .running,
    risk: .mutation, approvalGranted: false, hasValidationPlan: true, leaseExpiresAt: nil)
  #expect(job.recoveryDecision() == .failClosed)
}

@Test func workerRecoveryPolicyRequiresValidationForApprovedMutation() {
  let unsafe = WorkerJobContract(commandId: "C1", sessionId: "S1", state: .running,
    risk: .mutation, approvalGranted: true, hasValidationPlan: false, leaseExpiresAt: nil)
  let resumable = WorkerJobContract(commandId: "C1", sessionId: "S1", state: .running,
    risk: .mutation, approvalGranted: true, hasValidationPlan: true, leaseExpiresAt: nil)
  #expect(unsafe.recoveryDecision() == .failClosed)
  #expect(resumable.recoveryDecision() == .resume)
}

@Test func workerRecoveryPolicyDoesNotDuplicateAnActiveLease() {
  let job = WorkerJobContract(commandId: "C1", sessionId: "S1", state: .running,
    risk: .readOnly, approvalGranted: false, hasValidationPlan: false,
    leaseExpiresAt: Date().addingTimeInterval(60))
  #expect(job.recoveryDecision() == .observeActiveLease)
}
