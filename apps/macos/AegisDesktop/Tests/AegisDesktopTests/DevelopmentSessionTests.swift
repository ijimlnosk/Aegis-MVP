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

@Test func developerIntentsResolveExplicitTrustedProject() throws {
  let project = try DeveloperTestSupport.gitProject()
  try #"{"scripts":{"typecheck":"echo ok","lint":"echo ok","test":"echo ok"}}"#
    .write(to: project.appending(path: "package.json"), atomically: true, encoding: .utf8)
  let (memory, _) = try DeveloperTestSupport.repositories(project: project)
  #expect(DeveloperIntentResolver.plan(for: "PTFriends 작업 시작하자", repository: memory)?.steps.map(\.action)
    == [.openProject, .startDevelopmentSession, .getProjectHealth])
  #expect(DeveloperIntentResolver.plan(for: "PTFriends 어디까지 했지?", repository: memory)?.steps.first?.action
    == .getDevelopmentRecap)
  let readiness = DeveloperIntentResolver.plan(for: "PTFriends 배포 준비됐어?", repository: memory)
  #expect(readiness?.steps.count == 4)
  #expect(readiness?.steps.contains { $0.action == .runProjectBuild } == false)
  #expect(readiness?.steps.last?.action == .assessProjectDeploymentReadiness)
}
