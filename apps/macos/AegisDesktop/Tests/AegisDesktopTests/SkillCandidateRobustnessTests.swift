import Foundation
import Testing
@testable import AegisDesktop

@Test func emptyOneAndTwoItemHistoriesAreSafe() throws {
  let detector = SkillCandidateDetector()
  #expect(detector.detect(records: []) == nil)
  #expect(detector.detect(records: [try record("a", "get_server_status", "")]) == nil)
  let two = [try record("same", "get_server_status", ""),
    try record("same", "get_docker_containers", "")]
  #expect(detector.detect(records: two) == nil)
}

@Test func threeIdenticalActionsCanCreateCandidate() throws {
  let records = try (0..<3).map { _ in try record("서버 상태", "get_server_status", "sol-server") }
  let candidate = SkillCandidateDetector().detect(records: records)
  #expect(candidate?.steps.map(\.action) == [.getServerStatus])
}

@Test func repeatedTwoAndThreeStepPatternsAreSafe() throws {
  let two = try histories(actions: ["get_server_status", "get_docker_containers"], repetitions: 3)
  let three = try histories(actions: ["get_server_status", "get_docker_containers", "get_system_status"], repetitions: 3)
  #expect(SkillCandidateDetector().detect(records: two)?.steps.count == 2)
  #expect(SkillCandidateDetector().detect(records: three)?.steps.count == 3)
}

@Test func partialOddAndNonRepeatingHistoriesDoNotCrash() throws {
  let partial = try histories(actions: ["get_server_status", "get_docker_containers"], repetitions: 2)
    + [try record("pattern", "get_server_status", "")]
  let odd = try histories(actions: ["get_server_status"], repetitions: 5)
  let different = try ["get_server_status", "get_docker_containers", "get_system_status"]
    .map { try record("different", $0, "") }
  #expect(SkillCandidateDetector().detect(records: partial) == nil)
  #expect(SkillCandidateDetector().detect(records: odd) != nil)
  #expect(SkillCandidateDetector().detect(records: different) == nil)
}

@Test func malformedHistoryAndProjectStatusCompletionAreSafe() throws {
  let malformed = MemoryRecord(type: .actionHistory, key: "bad", value: "{missing")
  let status = try record("PTFriends 상태 보여줘", "get_remembered_project_status", "PTFriends")
  let detector = SkillCandidateDetector()
  #expect(detector.detect(records: [malformed]) == nil)
  #expect(detector.detect(records: [status]) == nil)
}

@Test func proposalFailureDoesNotFailCompletedActionOrNextRequest() throws {
  let project = AgentStep(action: .getRememberedProjectStatus, project: "PTFriends")
  var first = try AgentPlanExecutor(plan: AgentPlan(step: project), request: "PTFriends 상태 보여줘")
  _ = first.next(); let firstCompleted = first.complete(project.id, succeeded: true)
  #expect(firstCompleted)
  let analysis = SkillProposalAnalysis.detect(loadHistory: { throw DetectionFailure.test },
    loadSkills: { [] })
  guard case .failure = analysis else { Issue.record("failure boundary did not catch"); return }
  #expect(first.state.outcomes[project.id] == .succeeded)
  let server = AgentStep(action: .getServerStatus)
  var second = try AgentPlanExecutor(plan: AgentPlan(step: server), request: "sol-server 상태 보여줘")
  guard case .execute = second.next() else { Issue.record("next request unusable"); return }
  let secondCompleted = second.complete(server.id, succeeded: true)
  #expect(secondCompleted)
}

private func histories(actions: [String], repetitions: Int) throws -> [MemoryRecord] {
  let values = (0..<repetitions).flatMap { _ in actions }
  return try values.enumerated().map { index, action in
    try record("pattern", action, "", timestamp: Date(timeIntervalSince1970: Double(index)))
  }
}
private func record(_ request: String, _ action: String, _ target: String,
                    timestamp: Date = .now) throws -> MemoryRecord {
  let value = ActionHistoryValue(request: request, action: action, target: target,
    result: "ignored", succeeded: true, timestamp: timestamp)
  let data = try JSONEncoder().encode(value)
  guard let json = String(data: data, encoding: .utf8) else { throw DetectionFailure.test }
  return MemoryRecord(type: .actionHistory, key: UUID().uuidString, value: json)
}
private enum DetectionFailure: Error { case test }
