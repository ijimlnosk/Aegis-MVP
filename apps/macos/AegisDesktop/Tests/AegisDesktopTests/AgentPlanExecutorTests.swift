import Testing
@testable import AegisDesktop

@Test func independentReadsContinueAfterFailure() throws {
  let first = AgentStep(action: .getServerStatus)
  let second = AgentStep(action: .getDockerContainers)
  var executor = try AgentPlanExecutor(plan: AgentPlan(steps: [first, second]), request: "서버 조회")
  _ = executor.next()
  let completed = executor.complete(first.id, succeeded: false)
  #expect(completed)
  guard case .execute(let step, _, _) = executor.next() else { Issue.record("independent read did not continue"); return }
  #expect(step.id == second.id)
}

@Test func dangerousActionPausesAndApprovalResumes() throws {
  let restart = AgentStep(action: .restartDockerContainer, container: "dksfhomepage")
  var executor = try AgentPlanExecutor(plan: AgentPlan(step: restart), request: "재시작")
  guard case .approval = executor.next() else { Issue.record("approval was not requested"); return }
  let approved = executor.approve(restart.id)
  #expect(approved)
  guard case .execute(let step, _, _) = executor.next() else { Issue.record("approval did not resume"); return }
  #expect(step.id == restart.id)
}

@Test func rejectionPreventsMutationAndSkipsDependentStep() throws {
  let restart = AgentStep(action: .restartDockerContainer, container: "dksfhomepage")
  let status = AgentStep(action: .getServerStatus, dependency: .requiresPreviousSuccess)
  var executor = try AgentPlanExecutor(plan: AgentPlan(steps: [restart, status]), request: "재시작 후 상태")
  _ = executor.next()
  let rejected = executor.reject(restart.id)
  #expect(rejected)
  guard case .skipped(let step, _, _) = executor.next() else { Issue.record("dependent step was not skipped"); return }
  #expect(step.id == status.id)
  #expect(executor.state.outcomes[restart.id] == .rejected)
}

@Test func approvalThenContinuesToDependentRead() throws {
  let restart = AgentStep(action: .restartDockerContainer, container: "dksfhomepage")
  let status = AgentStep(action: .getServerStatus, dependency: .requiresPreviousSuccess)
  var executor = try AgentPlanExecutor(plan: AgentPlan(steps: [restart, status]), request: "재시작 후 상태")
  _ = executor.next(); _ = executor.approve(restart.id); _ = executor.next()
  let completed = executor.complete(restart.id, succeeded: true)
  #expect(completed)
  guard case .execute(let step, _, _) = executor.next() else { Issue.record("dependent read did not continue"); return }
  #expect(step.id == status.id)
}
