import Foundation
import Testing
@testable import AegisDesktop

@Test func projectDiscoveryFindsAGitProjectByExactFolderNameUnderASearchRoot() throws {
  let root = try DeveloperTestSupport.directory()
  let project = root.appending(path: "aegis-mvp")
  try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: project.appending(path: ".git"), withIntermediateDirectories: true)
  let found = ProjectDiscovery.find(named: "Aegis-MVP", searchRoots: [root])
  #expect(found?.hasSuffix("/aegis-mvp") == true)
}

@Test func projectDiscoveryIgnoresAFolderWithoutGit() throws {
  let root = try DeveloperTestSupport.directory()
  let notAProject = root.appending(path: "aegis-mvp")
  try FileManager.default.createDirectory(at: notAProject, withIntermediateDirectories: true)
  #expect(ProjectDiscovery.find(named: "Aegis-MVP", searchRoots: [root]) == nil)
}

@Test func projectDiscoveryReturnsNilWhenNoFolderMatchesTheName() throws {
  let root = try DeveloperTestSupport.directory()
  #expect(ProjectDiscovery.find(named: "DoesNotExist", searchRoots: [root]) == nil)
}

@Test func projectDiscoveryConfirmationParserRecognizesConfirmationPhrases() {
  #expect(ProjectDiscoveryConfirmationParser.isConfirmation("등록해"))
  #expect(ProjectDiscoveryConfirmationParser.isConfirmation("응 등록해줘"))
  #expect(ProjectDiscoveryConfirmationParser.isConfirmation("등록 해줘"))
  #expect(!ProjectDiscoveryConfirmationParser.isConfirmation("아니 됐어"))
  #expect(!ProjectDiscoveryConfirmationParser.isConfirmation("PTFriends 상태 보여줘"))
}
