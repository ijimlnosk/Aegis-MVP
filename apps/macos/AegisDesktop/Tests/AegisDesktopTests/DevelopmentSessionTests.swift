import Foundation
import Testing
@testable import AegisDesktop

@Test func developmentSessionStartsEndsAndPersists() throws {
  let project = try DeveloperTestSupport.gitProject()
  let (memory, repository) = try DeveloperTestSupport.repositories(project: project)
  let coordinator = DevelopmentSessionCoordinator(sessions: repository, memory: memory)
  #expect(try coordinator.start(project: "PTFriends").contains("시작"))
  try "work\n".write(to: project.appending(path: "work.txt"), atomically: true, encoding: .utf8)
  #expect(try coordinator.end(project: "PTFriends").contains("마무리"))
  let reopened = DevelopmentSessionRepository(databaseURL: repository.databaseURL)
  let saved = try reopened.sessions(project: "PTFriends")
  #expect(saved.count == 1)
  #expect(saved.first?.endedAt != nil)
}

@Test func recapSeparatesGitAndAegisActivity() throws {
  let project = try DeveloperTestSupport.gitProject()
  let (memory, repository) = try DeveloperTestSupport.repositories(project: project)
  let coordinator = DevelopmentSessionCoordinator(sessions: repository, memory: memory)
  _ = try coordinator.start(project: "PTFriends")
  let recap = try coordinator.recap(project: "PTFriends")
  #expect(recap.contains("최근 커밋"))
  #expect(recap.contains("Aegis 활동"))
}

@Test func cleanAndDirtyRecapsAreBothSuccessfulExecutionStates() throws {
  let project = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: project) }
  let (memory, repository) = try DeveloperTestSupport.repositories(project: project)
  let coordinator = DevelopmentSessionCoordinator(sessions: repository, memory: memory)
  let clean = try coordinator.recapResult(project: "PTFriends")
  #expect(clean.executionStatus == .succeeded); #expect(clean.projectState == .clean)
  try "changed\n".write(to: project.appending(path: "README.md"), atomically: true, encoding: .utf8)
  try "new\n".write(to: project.appending(path: "new file.ts"), atomically: true, encoding: .utf8)
  let dirty = try coordinator.recapResult(project: "PTFriends")
  #expect(dirty.executionStatus == .succeeded); #expect(dirty.projectState == .dirty)
  #expect(dirty.changedFiles.contains { $0.contains("README.md") })
  #expect(dirty.changedFiles.contains { $0.contains("new file.ts") })
  #expect(dirty.warnings.contains { $0.contains("미커밋 변경 2건") })
}

@Test func recapWithoutSessionOrAutonomousHistoryOmitsOptionalSections() throws {
  let project = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: project) }
  let (memory, repository) = try DeveloperTestSupport.repositories(project: project)
  let result = try DevelopmentSessionCoordinator(sessions: repository, memory: memory)
    .recapResult(project: "PTFriends")
  #expect(result.executionStatus == .succeeded); #expect(result.sessionSummary == nil)
  #expect(result.recentAutonomousTask == nil)
  let text = DevelopmentRecapFormatter.format(result)
  #expect(!text.contains("Aegis 활동:")); #expect(!text.contains("최근 Aegis 작업:"))
}

@Test func recapIncludesActiveSessionAndBoundedAutonomousHistory() throws {
  let project = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: project) }
  let (memory, repository) = try DeveloperTestSupport.repositories(project: project)
  let coordinator = DevelopmentSessionCoordinator(sessions: repository, memory: memory)
  _ = try coordinator.start(project: "PTFriends")
  let history = AutonomousDevelopmentHistory(candidateId: UUID(), projectId: "ptfriends",
    category: .bug, title: "오류 하나 수정", outcome: .succeeded, provider: "Codex",
    changedFileCount: 1, validationSummary: "typecheck:passed", repairAttempted: false,
    timestamp: .now)
  let value = String(data: try JSONEncoder().encode(history), encoding: .utf8)!
  _ = try memory.save(MemoryRecord(type: .actionHistory,
    key: "autonomous:\(history.candidateId)", value: value, source: "aegis"))
  let result = try coordinator.recapResult(project: "PTFriends")
  #expect(result.executionStatus == .succeeded); #expect(result.sessionSummary != nil)
  #expect(result.recentAutonomousTask?.title == "오류 하나 수정")
  let text = DevelopmentRecapFormatter.format(result)
  #expect(text.contains("최근 Aegis 작업:")); #expect(text.contains("typecheck:passed"))
}

@Test func exactDirtyDevRecapIsSuccessfulAndDoesNotCreateFailureSummary() throws {
  let project = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: project) }
  _ = try DeveloperTestSupport.process("/usr/bin/git", ["checkout", "-b", "dev"], at: project)
  try "changed\n".write(to: project.appending(path: "README.md"), atomically: true, encoding: .utf8)
  try "a\n".write(to: project.appending(path: "one.ts"), atomically: true, encoding: .utf8)
  try "b\n".write(to: project.appending(path: "two.ts"), atomically: true, encoding: .utf8)
  let (memory, repository) = try DeveloperTestSupport.repositories(project: project)
  let coordinator = DevelopmentSessionCoordinator(sessions: repository, memory: memory)
  _ = try coordinator.start(project: "PTFriends")
  let result = try coordinator.recapResult(project: "PTFriends")
  #expect(result.branch == "dev"); #expect(result.changedFiles.count == 3)
  var executor = try AgentPlanExecutor(plan: AgentPlan(step: AgentStep(
    action: .getDevelopmentRecap, project: "PTFriends")), request: "ptfriends 어디까지 했지?")
  guard case .execute(let step, _, _) = executor.next() else { return }
  let completed = executor.complete(step.id, succeeded: result.executionStatus == .succeeded,
    result: DevelopmentRecapFormatter.format(result)); #expect(completed)
  guard case .finished(let summary) = executor.next() else { return }
  #expect(summary.status == .succeeded)
  #expect(PlanExecutionFormatter.format(summary, plan: executor.state.plan,
    request: executor.state.request) == nil)
}

@Test func missingProjectAndNonGitProjectAreActualRecapFailures() throws {
  let project = try DeveloperTestSupport.gitProject(); defer { try? FileManager.default.removeItem(at: project) }
  let (memory, repository) = try DeveloperTestSupport.repositories(project: project)
  let coordinator = DevelopmentSessionCoordinator(sessions: repository, memory: memory)
  #expect(throws: Error.self) { try coordinator.recapResult(project: "Missing") }
  let plain = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: plain) }
  let (plainMemory, plainSessions) = try DeveloperTestSupport.repositories(project: plain)
  #expect(throws: Error.self) {
    try DevelopmentSessionCoordinator(sessions: plainSessions, memory: plainMemory)
      .recapResult(project: "PTFriends")
  }
}

@Test func developerIntentsResolveExplicitTrustedProject() throws {
  let project = try DeveloperTestSupport.gitProject()
  try #"{"scripts":{"typecheck":"echo ok","lint":"echo ok","test":"echo ok"}}"#
    .write(to: project.appending(path: "package.json"), atomically: true, encoding: .utf8)
  let (memory, _) = try DeveloperTestSupport.repositories(project: project)
  #expect(DeveloperIntentResolver.plan(for: "PTFriends 작업 시작하자", repository: memory)?.steps.map(\.action)
    == [.openProject, .startDevelopmentSession, .getProjectHealth])
  #expect(DeveloperIntentResolver.plan(for: "PTFriends 어디까지 했지?", repository: memory)?.steps.first?.action
    == .getDevelopmentRecap)
  // Present-progressive phrasing ("뭐하고있지") previously missed the "뭐 했" keyword and fell
  // through to the LLM planner, which picked openProject and failed validation (missing/invalid
  // editor). It must resolve deterministically to the same recap action as "어디까지 했지".
  #expect(DeveloperIntentResolver.plan(for: "ptfriends 지금 뭐하고있지?", repository: memory)?.steps.first?.action
    == .getDevelopmentRecap)
  #expect(DeveloperIntentResolver.plan(for: "PTFriends 뭐해?", repository: memory)?.steps.first?.action
    == .getDevelopmentRecap)
  let readiness = DeveloperIntentResolver.plan(for: "PTFriends 배포 준비됐어?", repository: memory)
  #expect(readiness?.steps.count == 4)
  #expect(readiness?.steps.contains { $0.action == .runProjectBuild } == false)
  #expect(readiness?.steps.last?.action == .assessProjectDeploymentReadiness)
}

@Test func unregisteredProjectStatusQueryExplainsHowToRegisterInsteadOfFallingThroughToTheLLM() throws {
  let project = try DeveloperTestSupport.gitProject()
  let (memory, _) = try DeveloperTestSupport.repositories(project: project)
  let plan = DeveloperIntentResolver.plan(for: "Aegis-MVP 상태 보여줘", repository: memory)
  #expect(plan?.steps.isEmpty == true)
  let answer = try #require(plan?.finalAnswer)
  #expect(answer.contains("Aegis-MVP"))
  #expect(answer.contains("등록"))
  #expect(answer.contains("PTFriends"))
}

@Test func plainTextWithNoStatusIntentStillFallsThroughWhenProjectIsUnknown() throws {
  let project = try DeveloperTestSupport.gitProject()
  let (memory, _) = try DeveloperTestSupport.repositories(project: project)
  #expect(DeveloperIntentResolver.plan(for: "안녕하세요", repository: memory) == nil)
}

@Test func locateProjectPlanAnswersDirectlyWhenAlreadyRegistered() throws {
  let project = try DeveloperTestSupport.gitProject()
  let (memory, _) = try DeveloperTestSupport.repositories(project: project)
  let plan = DeveloperIntentResolver.plan(for: "PTFriends 위치 찾아줘", repository: memory)
  #expect(plan?.steps.isEmpty == true)
  let answer = try #require(plan?.finalAnswer)
  #expect(answer.contains("PTFriends"))
  #expect(answer.contains(project.path))
}

@Test func locateProjectPlanEmitsFindProjectPathStepWhenUnregistered() throws {
  let project = try DeveloperTestSupport.gitProject()
  let (memory, _) = try DeveloperTestSupport.repositories(project: project)
  let plan = DeveloperIntentResolver.plan(for: "Aegis-MVP 위치 찾아줘", repository: memory)
  #expect(plan?.steps.count == 1)
  #expect(plan?.steps.first?.action == .findProjectPath)
  #expect(plan?.steps.first?.content == "Aegis-MVP")
}
