import Testing
@testable import AegisDesktop

private let validationActions: [AgentAction] = [.runProjectTypecheck, .runProjectLint,
  .runProjectTests, .runProjectBuild]

@Test func validationRunsWithoutApprovalOnlyForAllowlistedProjects() throws {
  for action in validationActions {
    #expect(ApprovalPolicy.risk(for: action) == .safeValidation)
    #expect(action.runsProjectScript)
    let step = AgentStep(action: action, project: "PTFriends")
    var executor = try AgentPlanExecutor(plan: AgentPlan(step: step), request: "PTFriends 전체 점검",
      autoValidationProjects: ["ptfriends"])
    guard case .execute = executor.next() else {
      Issue.record("\(action.rawValue) unexpectedly requested approval"); continue
    }
  }
}

@Test func validationForUnlistedProjectWaitsForApproval() throws {
  for action in validationActions {
    let step = AgentStep(action: action, project: "SoolSool")
    var executor = try AgentPlanExecutor(plan: AgentPlan(step: step), request: "SoolSool 전체 점검",
      autoValidationProjects: ["ptfriends"])
    guard case .approval = executor.next() else {
      Issue.record("\(action.rawValue) ran without approval"); continue
    }
    let approved = executor.approve(step.id); #expect(approved)
    guard case .execute = executor.next() else { Issue.record("approved step did not run"); continue }
  }
}

@Test func autoValidationProjectsParseCaseInsensitiveList() {
  let names = AutoValidationProjects.names(from: [AutoValidationProjects.environmentKey: " Aegis-MVP, PTFriends ,,"])
  #expect(names == ["aegis-mvp", "ptfriends"])
  #expect(AutoValidationProjects.allows("PTFRIENDS", in: names))
  #expect(!AutoValidationProjects.allows("ptf", in: names))
  #expect(!AutoValidationProjects.allows(nil, in: names))
  #expect(AutoValidationProjects.names(from: [:]).isEmpty)
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
  var executor = try AgentPlanExecutor(plan: AgentPlan(step: step), request: "PTFriends build 검사",
    autoValidationProjects: ["ptfriends"])
  _ = executor.next()
  let result = ProjectValidationResult(check: .build, status: .unsupported,
    summary: "build 검사를 건너뜁니다.")
  #expect(result.succeedsPlan)
  let completed = executor.complete(step.id, succeeded: result.succeedsPlan)
  #expect(completed)
  guard case .finished = executor.next() else { Issue.record("unsupported check failed the plan"); return }
}

@Test func codingVerificationRunsScriptsOnlyWithApprovalOrAllowlist() {
  let step = AgentStep(action: .verifyCodingTask, project: "PTFriends")
  #expect(ApprovalPolicy.requiresApproval(for: step, autoValidationProjects: []))
  #expect(!ApprovalPolicy.requiresApproval(for: step, autoValidationProjects: ["ptfriends"]))
}
