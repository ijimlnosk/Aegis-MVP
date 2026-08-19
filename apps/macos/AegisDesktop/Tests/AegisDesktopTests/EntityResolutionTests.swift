import Foundation
import Testing
@testable import AegisDesktop

@Test func ptFriendsResolvesAsProjectAndStartIsNotDocker() throws {
  let repository = try entityRepository()
  try repository.save(MemoryRecord(type: .project, key: "PTFriends",
    value: "/Users/test/ptfriends"))
  let entity = ProjectEntityResolver.resolve(in: "PTFriends 시작해",
    repository: repository, environment: [:])
  let plan = ProjectIntentResolver.plan(for: "PTFriends 시작해", repository: repository)
  #expect(entity?.name == "PTFriends")
  #expect(plan?.steps.first?.action == .openProject)
  #expect(plan?.steps.contains { $0.action.isDockerMutation } == false)
}

@Test func projectAliasResolvesToCanonicalProject() throws {
  let repository = try entityRepository()
  try repository.save(MemoryRecord(type: .project, key: "PTFriends", value: "/tmp/ptfriends"))
  try repository.save(MemoryRecord(type: .alias, key: "피티친구", value: "PTFriends"))
  let plan = ProjectIntentResolver.plan(for: "피티친구 열어", repository: repository)
  #expect(plan?.steps.first?.project == "PTFriends")
}

@Test func registeredProjectCannotBeImplicitContainer() {
  let project = ProjectEntity(name: "PTFriends", aliases: ["피티친구"])
  let inventory = [DockerContext(name: "PTFriends", state: "Exited", isRunning: false)]
  let result = ContainerTargetValidator.validate("PTFriends", inventory: inventory,
    knownProjects: [project], explicitDockerContext: false)
  #expect(result == .failure(.project("PTFriends")))
}

@Test func explicitKnownDockerRestartUsesExactContainer() {
  let step = ServerIntentParser.parse("dksfhomepage 컨테이너 재시작해")
  let inventory = [DockerContext(name: "dksfhomepage", state: "Up", isRunning: true)]
  let result = ContainerTargetValidator.validate(step?.container ?? "", inventory: inventory,
    knownProjects: [], explicitDockerContext: true)
  #expect(step?.action == .restartDockerContainer)
  #expect(result == .success("dksfhomepage"))
  #expect(step?.action.requiresApproval == true)
}

@Test func nonexistentAndTypoContainerMutationsAreBlocked() {
  let inventory = [DockerContext(name: "dksfhomepage", state: "Up", isRunning: true)]
  #expect(ContainerTargetValidator.validate("missing", inventory: inventory,
    knownProjects: [], explicitDockerContext: true) == .failure(.unknown("missing")))
  #expect(ContainerTargetValidator.validate("dksfhomepaeg", inventory: inventory,
    knownProjects: [], explicitDockerContext: true) == .failure(.unknown("dksfhomepaeg")))
}

@Test func learnedSkillMustRevalidateContainerTarget() throws {
  let skill = LearnedSkill(name: "잘못된 복구", description: "", steps: [
    AgentStep(action: .restartDockerContainer, container: "PTFriends"),
  ])
  try SkillValidator.validate(skill)
  let result = ContainerTargetValidator.validate(skill.steps[0].container ?? "",
    inventory: [], knownProjects: [ProjectEntity(name: "PTFriends", aliases: [])],
    explicitDockerContext: false)
  #expect(result == .failure(.project("PTFriends")))
}

private func entityRepository() throws -> MemoryRepository {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "aegis-entity-tests-\(UUID().uuidString)/memory.sqlite")
  let repository = MemoryRepository(databaseURL: url); try repository.bootstrap(); return repository
}
