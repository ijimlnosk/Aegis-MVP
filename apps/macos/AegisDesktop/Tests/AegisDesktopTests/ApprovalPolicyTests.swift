import Testing
@testable import AegisDesktop

@Test func trustedValidationActionsRunWithoutApproval() throws {
  let actions: [AgentAction] = [.runProjectTypecheck, .runProjectLint,
    .runProjectTests, .runProjectBuild]
  for action in actions {
    #expect(ApprovalPolicy.risk(for: action) == .safeValidation)
    #expect(!action.requiresApproval)
    let step = AgentStep(action: action, project: "PTFriends")
    var executor = try AgentPlanExecutor(plan: AgentPlan(step: step), request: "PTFriends 전체 점검")
    guard case .execute = executor.next() else {
      Issue.record("\(action.rawValue) unexpectedly requested approval"); continue
    }
  }
}

@Test func mutationRisksStillRequireApproval() {
  #expect(ApprovalPolicy.risk(for: .restartDockerContainer) == .remoteMutation)
  #expect(ApprovalPolicy.requiresApproval(for: .restartDockerContainer))
  #expect(ApprovalPolicy.requiresApproval(for: .remoteMutation))
  #expect(ApprovalPolicy.requiresApproval(for: .destructive))
  #expect(AgentAction(rawValue: "git_push") == nil)
  #expect(AgentAction(rawValue: "run_command") == nil)
  #expect(AgentAction(rawValue: "execute_shell") == nil)
}

@Test func unsupportedValidationCompletesPlanSuccessfully() throws {
  let step = AgentStep(action: .runProjectBuild, project: "PTFriends")
  var executor = try AgentPlanExecutor(plan: AgentPlan(step: step), request: "PTFriends build 검사")
  _ = executor.next()
  let result = ProjectValidationResult(check: .build, status: .unsupported,
    summary: "build 검사를 건너뜁니다.")
  #expect(result.succeedsPlan)
  let completed = executor.complete(step.id, succeeded: result.succeedsPlan)
  #expect(completed)
  guard case .finished = executor.next() else { Issue.record("unsupported check failed the plan"); return }
}
