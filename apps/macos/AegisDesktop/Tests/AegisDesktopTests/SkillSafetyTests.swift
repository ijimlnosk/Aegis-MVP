import Foundation
import Testing
@testable import AegisDesktop

@Test func readOnlySkillExecutesWithoutApproval() throws {
  let skill = LearnedSkill(name: "서버 점검", description: "", steps: readSteps())
  var executor = try AgentPlanExecutor(plan: AgentPlan(steps: skill.steps), request: "서버 점검해", isLearnedSkill: true)
  guard case .execute = executor.next() else { Issue.record("read skill paused"); return }
}

@Test func dangerousSkillStillPausesAndRejectionPreventsMutation() throws {
  let logs = AgentStep(action: .getDockerLogs, container: "dksfhomepage")
  let restart = AgentStep(action: .restartDockerContainer, dependency: .requiresPreviousSuccess,
    container: "dksfhomepage")
  var executor = try AgentPlanExecutor(plan: AgentPlan(steps: [logs, restart]),
    request: "웹서버 다시 살려", isLearnedSkill: true)
  _ = executor.next(); _ = executor.complete(logs.id, succeeded: true)
  guard case .approval = executor.next() else { Issue.record("dangerous skill did not pause"); return }
  let rejected = executor.reject(restart.id)
  #expect(rejected)
  #expect(executor.state.outcomes[restart.id] == .rejected)
}

@Test func maliciousSkillPayloadDecodesAsUnknownAndFailsValidation() throws {
  let json = """
  {"action":"rm -rf /","dependency":"independent"}
  """
  let step = try JSONDecoder().decode(AgentStep.self, from: Data(json.utf8))
  #expect(step.action == .unknown)
  let skill = LearnedSkill(name: "malicious", description: "", steps: [step])
  #expect(!SkillValidator.errors(in: skill).isEmpty)
}

@Test func taughtDangerousSkillKeepsTypedApprovalAction() {
  guard case .teach(_, _, let plan) = SkillIntentParser.parse(
    "웹서버 다시 살려라고 하면 dksfhomepage 로그 보고 재시작해") else {
    Issue.record("dangerous teaching not parsed"); return
  }
  #expect(plan.steps.map(\.action) == [.getDockerLogs, .restartDockerContainer])
  #expect(plan.steps.last?.action.requiresApproval == true)
}

private func readSteps() -> [AgentStep] {
  [AgentStep(action: .getServerStatus), AgentStep(action: .getDockerContainers)]
}
