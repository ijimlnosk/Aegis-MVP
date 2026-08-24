import Foundation
import Testing
@testable import AegisDesktop

@Test func onlyOneUIWorkflowRunsAtATimeAndLaterRequestStillWorks() async throws {
  let coordinator = UIInteractionCoordinator()
  let first = Task { try await coordinator.perform(target: "VSCode") {
    try await Task.sleep(for: .milliseconds(50)); return "done"
  } }
  try await Task.sleep(for: .milliseconds(5))
  await #expect(throws: UIInteractionError.self) {
    _ = try await coordinator.perform(target: "Xcode") { "unexpected" }
  }
  #expect(try await first.value == "done")
  #expect(try await coordinator.perform(target: "Xcode") { "recovered" } == "recovered")
}
