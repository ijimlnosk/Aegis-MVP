import Foundation
import Testing
@testable import AegisDesktop

@Test func knownPTFriendsProjectResolvesForVSCode() throws {
  let directory = try temporaryProject()
  let repository = try openingRepository()
  let result = ProjectOpeningService.resolve(project: "PTFriends", application: "VSCode",
    repository: repository, environment: ["PTFRIENDS_PROJECT_ROOT": directory.path])
  #expect(result == .success(ResolvedProjectOpening(project: "PTFriends",
    application: "Visual Studio Code", path: directory.path)))
}

@Test func projectAliasResolvesToTrustedPath() throws {
  let directory = try temporaryProject(), repository = try openingRepository()
  try repository.save(MemoryRecord(type: .project, key: "SoolSool", value: directory.path))
  try repository.save(MemoryRecord(type: .alias, key: "술술", value: "SoolSool"))
  let result = ProjectOpeningService.resolve(project: "술술", application: "Xcode",
    repository: repository, environment: [:])
  guard case .success(let opening) = result else { Issue.record("alias did not resolve"); return }
  #expect(opening.project == "SoolSool"); #expect(opening.path == directory.path)
}

@Test func unknownAndArbitraryPathProjectsAreRejected() throws {
  let repository = try openingRepository()
  #expect(ProjectOpeningService.resolve(project: "unknown", application: "VSCode",
    repository: repository, environment: [:]) == .failure(.unknownProject("unknown")))
  #expect(ProjectOpeningService.resolve(project: "/tmp/llm-generated", application: "VSCode",
    repository: repository, environment: [:]) == .failure(.unknownProject("/tmp/llm-generated")))
}

@Test func nonexistentRememberedPathIsRejectedSafely() throws {
  let repository = try openingRepository(), path = "/tmp/aegis-does-not-exist-\(UUID().uuidString)"
  try repository.save(MemoryRecord(type: .project, key: "PTFriends", value: path))
  #expect(ProjectOpeningService.resolve(project: "PTFriends", application: "VSCode",
    repository: repository, environment: [:]) == .failure(.invalidPath(path)))
}

@Test func explicitCursorOverridesRememberedVSCode() throws {
  let directory = try temporaryProject(), repository = try openingRepository()
  try repository.save(MemoryRecord(type: .project, key: "PTFriends", value: directory.path))
  try repository.save(MemoryRecord(type: .preference, key: "default_code_editor",
    value: "Visual Studio Code"))
  let plan = ProjectIntentResolver.plan(for: "Cursor로 PTFriends 열어줘", repository: repository)
  #expect(plan?.steps.first?.action == .openProject)
  #expect(plan?.steps.first?.application == "Cursor")
}

@Test func vscodeProjectPhrasesProduceTypedOpenProject() throws {
  let directory = try temporaryProject(), repository = try openingRepository()
  try repository.save(MemoryRecord(type: .project, key: "PTFriends", value: directory.path))
  let first = ProjectIntentResolver.plan(for: "VSCode에서 PTFriends 열어줘", repository: repository)
  let second = ProjectIntentResolver.plan(for: "PTFriends VSCode로 켜줘", repository: repository)
  #expect(first?.steps.first?.action == .openProject)
  #expect(first?.steps.first?.application == "Visual Studio Code")
  #expect(second?.steps.first?.action.requiresApproval == true)
}

@Test func unknownEditorIsRejected() throws {
  let directory = try temporaryProject(), repository = try openingRepository()
  try repository.save(MemoryRecord(type: .project, key: "PTFriends", value: directory.path))
  #expect(ProjectOpeningService.resolve(project: "PTFriends", application: "Sublime",
    repository: repository, environment: [:]) == .failure(.unknownEditor("Sublime")))
  let generated = ProjectIntentResolver.plan(for: "Sublime로 PTFriends 열어", repository: repository)
  let plan = try #require(generated)
  #expect(plan.steps.first?.application == "Sublime")
  #expect(!AgentPlanValidator.errors(in: plan, for: "Sublime로 PTFriends 열어").isEmpty)
}

@Test func defaultEditorPreferenceIsStoredAndUsed() throws {
  guard case .remember(let type, let key, let value) = MemoryIntentParser.parse(
    "내 기본 코드 에디터는 Cursor야") else { Issue.record("editor preference not parsed"); return }
  #expect(type == .preference); #expect(key == "default_code_editor"); #expect(value == "Cursor")
  let directory = try temporaryProject(), repository = try openingRepository()
  try repository.save(MemoryRecord(type: .project, key: "PTFriends", value: directory.path))
  try repository.save(MemoryRecord(type: type, key: key, value: value))
  let plan = ProjectIntentResolver.plan(for: "PTFriends 프로젝트 열어", repository: repository)
  #expect(plan?.steps.first?.application == "Cursor")
}

private func openingRepository() throws -> MemoryRepository {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "aegis-opening-tests-\(UUID().uuidString)/memory.sqlite")
  let repository = MemoryRepository(databaseURL: url); try repository.bootstrap(); return repository
}
private func temporaryProject() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appending(path: "aegis-project-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
}
