import Foundation
import Testing
@testable import AegisDesktop

@Test func repeatedPatternCreatesCandidateAtThreshold() {
  let detector = SkillCandidateDetector(threshold: 3)
  let sequences = (0..<3).map { _ in projectSequence() }
  let candidate = detector.detect(sequences: sequences)
  #expect(candidate?.evidenceCount == 3)
  #expect(candidate?.steps.count == 2)
}

@Test func patternBelowThresholdDoesNotCreateCandidate() {
  let detector = SkillCandidateDetector(threshold: 3)
  #expect(detector.detect(sequences: [projectSequence(), projectSequence()]) == nil)
}

@Test func patternNormalizationIgnoresUUIDButKeepsTargets() {
  let detector = SkillCandidateDetector(threshold: 2)
  #expect(detector.detect(sequences: [projectSequence(), projectSequence()]) != nil)
  let nginx = [AgentStep(action: .restartDockerContainer, container: "nginx")]
  let postgres = [AgentStep(action: .restartDockerContainer, container: "postgres")]
  #expect(detector.detect(sequences: [nginx, postgres]) == nil)
}

@Test func explicitSkillTeachingCreatesTypedPlan() {
  guard case .teach(let name, _, let plan) = SkillIntentParser.parse(
    "앞으로 서버 점검이라고 하면 sol-server 상태 보고 Docker 목록 보여줘") else {
    Issue.record("teaching intent not parsed"); return
  }
  #expect(name == "서버 점검")
  #expect(plan.steps.map(\.action) == [.getServerStatus, .getDockerContainers])
}

@Test func actionHistoryProducesRepeatedSequenceProposal() throws {
  let records = try (0..<3).flatMap { cycle -> [MemoryRecord] in
    let base = Date(timeIntervalSince1970: Double(cycle * 10))
    return [try history("PTFriends 열어", "open_application", "PTFriends", base),
      try history("PTFriends 상태 확인해", "get_remembered_project_status", "PTFriends",
        base.addingTimeInterval(1))]
  }
  let detector = SkillCandidateDetector(threshold: 3)
  let candidate = detector.detect(sequences: detector.sequences(from: records))
  #expect(candidate?.steps.map(\.action) == [.openApplication, .getRememberedProjectStatus])
  #expect(candidate?.steps.first?.application == "Visual Studio Code")
}

@Test func invalidAndOversizedSkillsAreRejected() {
  let invalid = LearnedSkill(name: "bad", description: "", steps: [
    AgentStep(action: .restartDockerContainer, container: nil),
  ])
  #expect(!SkillValidator.errors(in: invalid).isEmpty)
  let oversized = LearnedSkill(name: "large", description: "",
    steps: (0..<6).map { _ in AgentStep(action: .getServerStatus) })
  #expect(!SkillValidator.errors(in: oversized).isEmpty)
  let unknown = LearnedSkill(name: "unknown", description: "", steps: [AgentStep(action: .unknown)])
  #expect(!SkillValidator.errors(in: unknown).isEmpty)
  let command = LearnedSkill(name: "command", description: "",
    steps: [AgentStep(action: .setClipboard, content: "rm -rf /")])
  #expect(!SkillValidator.errors(in: command).isEmpty)
}

private func projectSequence() -> [AgentStep] {
  [AgentStep(action: .openApplication, application: "Visual Studio Code", project: "PTFriends"),
   AgentStep(action: .getRememberedProjectStatus, dependency: .requiresPreviousSuccess, project: "PTFriends")]
}

private func history(_ request: String, _ action: String, _ target: String,
                     _ timestamp: Date) throws -> MemoryRecord {
  let value = ActionHistoryValue(request: request, action: action, target: target,
    result: "ignored", succeeded: true, timestamp: timestamp)
  let json = String(data: try JSONEncoder().encode(value), encoding: .utf8)!
  return MemoryRecord(type: .actionHistory, key: UUID().uuidString, value: json)
}
