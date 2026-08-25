import Foundation
import Testing
@testable import AegisDesktop

@Test func codingTaskCarriesBoundedRemoteCorrelation() {
  let task = CodingTask(project: "PTFriends", projectRoot: URL(fileURLWithPath: "/tmp"),
    request: "inspect", mode: .readOnlyAnalysis,
    remoteSessionId: "phone", remoteCommandId: "command-1")
  #expect(task.remoteSessionId == "phone")
  #expect(task.remoteCommandId == "command-1")
}
