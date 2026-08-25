import AegisWorkerProtocol
import Foundation
import Testing

@Test func workerValidationResultRoundTripsInExecutionResult() throws {
  let check = WorkerValidationResult(check: "lint", status: "passed", exitCode: 0,
    summary: "ok")
  let value = WorkerExecutionResult(exitStatus: 0, stdout: Data(), hadStderr: false,
    timedOut: false, changedFiles: ["src/a.ts"], writeSafetyPassed: true,
    validations: [check], validationPassed: true)
  let restored = try JSONDecoder().decode(WorkerExecutionResult.self,
    from: JSONEncoder().encode(value))
  #expect(restored.validations == [check])
  #expect(restored.validationPassed == true)
}
