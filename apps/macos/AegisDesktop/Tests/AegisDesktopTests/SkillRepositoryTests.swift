import Foundation
import Testing
@testable import AegisDesktop

@Test func skillPersistsAcrossRepositoryRestart() throws {
  let url = skillDatabaseURL()
  let first = SkillRepository(databaseURL: url); try first.bootstrap()
  let skill = readSkill(); _ = try first.save(skill)
  let second = SkillRepository(databaseURL: url); try second.bootstrap()
  #expect(try second.find("서버 점검")?.steps.count == 2)
}

@Test func skillAliasMatchesButUnrelatedOrOverrideDoesNot() {
  let skill = LearnedSkill(name: "서버 점검", aliases: ["서버 살펴보기"], description: "", steps: readSkill().steps)
  #expect(SkillMatcher.match("서버 살펴보기 해줘", skills: [skill])?.id == skill.id)
  #expect(SkillMatcher.match("오늘 날씨 알려줘", skills: [skill]) == nil)
  #expect(SkillMatcher.match("서버 점검 말고 PTFriends 상태만 봐", skills: [skill]) == nil)
}

@Test func forgetAndRenameSkill() throws {
  let repository = SkillRepository(databaseURL: skillDatabaseURL()); try repository.bootstrap()
  let store = SkillStore(repository: repository); _ = try repository.save(readSkill())
  _ = try store.handle(.rename(old: "서버 점검", new: "인프라 확인"))
  #expect(try repository.find("인프라 확인") != nil)
  _ = try store.handle(.forget("인프라 확인"))
  #expect(try repository.skills().isEmpty)
}

@Test func usageUpdatesConfidenceWithoutRewritingSteps() throws {
  let repository = SkillRepository(databaseURL: skillDatabaseURL()); try repository.bootstrap()
  let original = readSkill(); _ = try repository.save(original)
  try repository.recordUsage(skill: original, request: "서버 점검해", succeeded: true)
  let foundAfterSuccess = try repository.find("서버 점검")
  let successful = try #require(foundAfterSuccess)
  #expect(successful.confidence > original.confidence)
  #expect(successful.steps.map(\.action) == original.steps.map(\.action))
  try repository.recordUsage(skill: successful, request: "서버 점검해", succeeded: false)
  let foundAfterFailure = try repository.find("서버 점검")
  let failed = try #require(foundAfterFailure)
  #expect(failed.confidence < successful.confidence)
  #expect(failed.steps.map(\.action) == original.steps.map(\.action))
  #expect(try repository.usages(skillID: original.id).count == 2)
}

private func readSkill() -> LearnedSkill {
  LearnedSkill(name: "서버 점검", aliases: ["서버 확인"], description: "read only", steps: [
    AgentStep(action: .getServerStatus), AgentStep(action: .getDockerContainers),
  ])
}
private func skillDatabaseURL() -> URL {
  FileManager.default.temporaryDirectory.appending(path: "aegis-skill-tests-\(UUID().uuidString)/memory.sqlite")
}
