import Foundation
import Testing
@testable import AegisDesktop

@Test func slashCommandParsesLeadingTokenCaseInsensitively() {
  #expect(SlashCommand.parse("/help") == .help)
  #expect(SlashCommand.parse("  /STATUS now ") == .status)
  #expect(SlashCommand.parse("/projects") == .projects)
  #expect(SlashCommand.parse("/unknown") == nil)
  #expect(SlashCommand.parse("help") == nil)
}

@Test func slashSuggestionsFilterByPrefixAndHideAfterArguments() {
  #expect(SlashCommand.suggestions(for: "/") == SlashCommand.allCases)
  #expect(SlashCommand.suggestions(for: "/st") == [.status])
  #expect(SlashCommand.suggestions(for: "/status now").isEmpty)
  #expect(SlashCommand.suggestions(for: "status").isEmpty)
}

@Test func slashResolverIgnoresNaturalLanguage() {
  #expect(SlashCommandResolver.resolve("PTFriends 상태 보여줘", projects: []) == nil)
  #expect(SlashCommandResolver.resolve("a/b 경로 열어줘", projects: []) == nil)
}

@Test func slashHelpListsEveryCommand() {
  guard case .message(let text) = SlashCommandResolver.resolve("/help", projects: []) else {
    Issue.record("help must be a direct message"); return
  }
  for command in SlashCommand.allCases { #expect(text.contains(command.usage)) }
}

@Test func slashStatusRunsOnlyAutomaticReadOnlyActions() {
  #expect(SlashCommandResolver.resolve("/status", projects: []) == .plan(SlashCommandResolver.statusActions))
  #expect(SlashCommandResolver.statusActions.count <= AgentPlan.maximumSteps)
  for action in SlashCommandResolver.statusActions {
    #expect(ApprovalPolicy.risk(for: action) == .safeRead)
  }
}

@Test func slashProjectsListsNamesAndAliasesWithoutPaths() {
  let projects = [ProjectEntity(name: "Aegis-MVP", aliases: [], path: "/secret/Aegis-MVP"),
    ProjectEntity(name: "PTFriends", aliases: ["피티"], path: "/secret/pt")]
  guard case .message(let text) = SlashCommandResolver.resolve("/projects", projects: projects) else {
    Issue.record("projects must be a direct message"); return
  }
  #expect(text.contains("- Aegis-MVP"))
  #expect(text.contains("- PTFriends (별칭: 피티)"))
  #expect(!text.contains("/secret"))
  guard case .message(let empty) = SlashCommandResolver.resolve("/projects", projects: []) else { return }
  #expect(empty.contains("등록된 프로젝트가 없습니다"))
}

@Test func unknownSlashCommandPointsToHelp() {
  guard case .message(let text) = SlashCommandResolver.resolve("/deploy", projects: []) else {
    Issue.record("unknown command must not reach the planner"); return
  }
  #expect(text.contains("/help"))
}
