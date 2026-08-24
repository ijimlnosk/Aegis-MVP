import Foundation
import Testing
@testable import AegisDesktop

private func candidate(title: String = "명확한 버그", confidence: Double = 0.9,
                       severity: DevelopmentTaskSeverity = .medium,
                       scope: DevelopmentTaskScope = .tiny, files: Int = 1,
                       validation: ValidationAvailability = .strong,
                       evidence: [String] = ["src/foo.ts:12"], dirty: Bool = false,
                       summary: String = "한 파일의 명확한 방어 로직") -> DevelopmentTaskCandidate {
  .init(id: UUID(), projectId: "ptfriends", projectName: "PTFriends", category: .bug,
    title: title, summary: summary, evidence: evidence, confidence: confidence,
    severity: severity, estimatedScope: scope, estimatedChangedFiles: files,
    validationStrategy: [.typecheck, .test], validationAvailability: validation,
    proposedAt: .now, overlapsExistingChanges: dirty)
}

@Test func autonomousConfigurationIsStrictlyBounded() {
  let defaults = AutonomousDevelopmentConfiguration.load([:])
  #expect(defaults.maximumChangedFiles == 5); #expect(defaults.maximumTasks == 1)
  #expect(defaults.repairAttempts == 1)
  let bounded = AutonomousDevelopmentConfiguration.load([
    "AEGIS_AUTONOMOUS_MAX_CHANGED_FILES": "999",
    "AEGIS_AUTONOMOUS_MAX_TASKS_PER_REQUEST": "9",
    "AEGIS_AUTONOMOUS_REPAIR_ATTEMPTS": "8"])
  #expect(bounded.maximumChangedFiles == 20); #expect(bounded.maximumTasks == 1)
  #expect(bounded.repairAttempts == 1)
}

@Test func highConfidenceSmallValidatedBugOutranksVagueArchitectureIdea() {
  let bounded = candidate()
  let vague = candidate(title: "전체 구조 개선", confidence: 0.55, severity: .high,
    scope: .large, files: 12, validation: .weak, summary: "large architecture rewrite")
  #expect(DevelopmentTaskScorer.best([vague, bounded])?.id == bounded.id)
}

@Test func autonomousPolicyRejectsLargeDangerousOrUnvalidatedTasks() {
  let config = AutonomousDevelopmentConfiguration.load([:])
  #expect(DevelopmentTaskPolicy.isExecutable(candidate(), configuration: config))
  #expect(!DevelopmentTaskPolicy.isExecutable(candidate(scope: .large, files: 9), configuration: config))
  #expect(!DevelopmentTaskPolicy.isExecutable(candidate(validation: .none), configuration: config))
  #expect(!DevelopmentTaskPolicy.isExecutable(candidate(summary: "database schema migration"), configuration: config))
}

@Test func temporaryCandidateExclusionsAreHonored() {
  let exclusions = DevelopmentTaskPolicy.exclusions(in: "로그 관련은 건드리지 마. 회원 기능은 제외해")
  #expect(!DevelopmentTaskPolicy.honors(candidate(title: "로그 제거"), exclusions: exclusions))
  #expect(DevelopmentTaskPolicy.honors(candidate(title: "날짜 처리 버그"), exclusions: exclusions))
}

@Test func autonomousDiscoveryPlanSelectsOneCandidateAndFirstStepIsIndependent() throws {
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let (memory, _) = try DeveloperTestSupport.repositories(project: root)
  let plan = AutonomousDevelopmentIntentResolver.plan(
    for: "PTFriends에서 지금 할 만한 작은 작업 하나 골라줘",
    repository: memory, active: nil)
  #expect(plan?.steps.map(\.action) == [.discoverDevelopmentTask, .proposeDevelopmentTask])
  #expect(plan?.steps.first?.dependency == .independent)
  #expect(plan?.steps.last?.dependency == .requiresPreviousSuccess)
  #expect(!ApprovalPolicy.requiresApproval(for: plan!.steps[0]))
  #expect(!ApprovalPolicy.requiresApproval(for: plan!.steps[1]))
}

@Test func autonomousExecutionPausesForApprovalAndResumesSameCandidate() throws {
  let selected = candidate()
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let plan = AutonomousDevelopmentIntentResolver.plan(for: "좋아 해봐",
    repository: try DeveloperTestSupport.repositories(project: root).0,
    active: selected)!
  var executor = try AgentPlanExecutor(plan: plan, request: "좋아 해봐")
  guard case .approval(let step, _, _) = executor.next() else { Issue.record("approval missing"); return }
  #expect(step.action == .executeDevelopmentTask)
  #expect(executor.state.executionState == .pausedForApproval)
  let approved = executor.approve(step.id); #expect(approved)
  guard case .execute(let resumed, _, _) = executor.next() else { Issue.record("resume missing"); return }
  #expect(resumed.id == step.id); #expect(resumed.content == selected.title)
}

@Test func autonomousRejectionIsCancellationAndNeverRunsWrite() throws {
  let selected = candidate()
  let root = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: root) }
  let (memory, _) = try DeveloperTestSupport.repositories(project: root)
  let plan = AutonomousDevelopmentIntentResolver.plan(for: "해봐", repository: memory, active: selected)!
  var executor = try AgentPlanExecutor(plan: plan, request: "해봐")
  guard case .approval(let step, _, _) = executor.next() else { return }
  let rejected = executor.reject(step.id); #expect(rejected)
  guard case .finished(let summary) = executor.next() else { return }
  #expect(summary.status == .cancelled); #expect(summary.succeededSteps.isEmpty)
}

@Test func autonomousActionsCannotRunProactively() {
  for action in [AgentAction.discoverDevelopmentTask, .proposeDevelopmentTask,
                 .executeDevelopmentTask, .repairDevelopmentTask] {
    #expect(!ProactivePolicy.mayAutoExecute(action))
  }
  #expect(ApprovalPolicy.requiresApproval(for: .executeDevelopmentTask))
  #expect(!ApprovalPolicy.requiresApproval(for: .discoverDevelopmentTask))
}

@Test func autonomousResultSeparatesExistingAndTaskChanges() {
  let result = AutonomousDevelopmentResult(candidate: candidate(), status: .succeeded,
    changedFiles: ["src/foo.ts", "src/bar.ts"], validation: [
      .init(check: .typecheck, status: .passed, summary: "ok")],
    preexistingCount: 6, repairAttempted: false, provider: "Codex")
  let text = AutonomousDevelopmentResultFormatter.format(result)
  #expect(text.contains("기존 미커밋 변경:\n6건 유지"))
  #expect(text.contains("src/foo.ts")); #expect(!text.contains("8 files"))
}

@Test func autonomousSurfaceAddsNoCommitPushDeployOrShellActions() {
  let names = Set(AgentAction.allCases.map(\.rawValue))
  for forbidden in ["commit", "push", "deploy", "run_shell", "execute_command"] {
    #expect(!names.contains(forbidden))
  }
}

@Test func autonomousOutcomeRequiresGitAndValidationAuthority() {
  #expect(AutonomousDevelopmentOutcomePolicy.resolve(first: .agentFailed, final: .agentFailed,
    repaired: false, changedCount: 1, limit: 5, scopeExpanded: false) == .agentFailed)
  #expect(AutonomousDevelopmentOutcomePolicy.resolve(first: .needsReview, final: .needsReview,
    repaired: false, changedCount: 0, limit: 5, scopeExpanded: false) == .needsReview)
  #expect(AutonomousDevelopmentOutcomePolicy.resolve(first: .failedValidation, final: .failedValidation,
    repaired: false, changedCount: 1, limit: 5, scopeExpanded: false) == .failedValidation)
  #expect(AutonomousDevelopmentOutcomePolicy.resolve(first: .timedOut, final: .timedOut,
    repaired: false, changedCount: 0, limit: 5, scopeExpanded: false) == .timedOut)
}

@Test func autonomousRepairIsSingleBoundedAndNeverExpandsSilently() {
  #expect(AutonomousDevelopmentOutcomePolicy.resolve(first: .failedValidation, final: .succeeded,
    repaired: true, changedCount: 2, limit: 5, scopeExpanded: false) == .succeeded)
  #expect(AutonomousDevelopmentOutcomePolicy.resolve(first: .failedValidation, final: .failedValidation,
    repaired: true, changedCount: 2, limit: 5, scopeExpanded: false) == .repairFailed)
  #expect(AutonomousDevelopmentOutcomePolicy.resolve(first: .failedValidation, final: .succeeded,
    repaired: true, changedCount: 6, limit: 5, scopeExpanded: false) == .needsReview)
  #expect(AutonomousDevelopmentOutcomePolicy.resolve(first: .failedValidation, final: .succeeded,
    repaired: true, changedCount: 2, limit: 5, scopeExpanded: true) == .needsReview)
}
