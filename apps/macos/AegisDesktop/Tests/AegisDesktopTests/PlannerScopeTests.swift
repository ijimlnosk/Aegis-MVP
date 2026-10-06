import Foundation
import Testing
@testable import AegisDesktop

@Test func everyPlannableActionBelongsToAtMostOneDomain() {
  let assigned = PlannerDomain.allCases.flatMap(\.actions)
  #expect(assigned.count == Set(assigned).count)
  #expect(Set(PlannerActionScope.full.actions) == Set(AgentAction.plannable))
}

@Test func fullPromptKeepsEveryRuleLine() {
  let full = AgentPlannerPrompt.system
  for domain in PlannerDomain.allCases { #expect(full.contains(AgentPlannerPrompt.guidance(domain))) }
  #expect(full.contains(AgentPlannerPrompt.coreRules))
  #expect(full.contains(AgentPlannerPrompt.closingRules))
  #expect(full.contains("run_command, execute_shell, terminal_command"))
}

@Test func dockerLogRequestNarrowsPromptAndSchema() {
  let scope = PlannerActionScope.select(for: "sol-server 도커 로그 보여줘", mentionsProject: false)
  #expect(scope.domains.contains(.server))
  #expect(!scope.domains.contains(.browser))
  #expect(!scope.domains.contains(.ui))
  #expect(scope.actions.contains(.getDockerLogs))
  #expect(!scope.actions.contains(.browserSearch))
  #expect(!scope.actions.contains(.kakaoMessage))
  let prompt = AgentPlannerPrompt.system(for: scope.domains)
  #expect(prompt.count < AgentPlannerPrompt.system.count)
  #expect(!prompt.contains(AgentPlannerPrompt.browserRules))
}

@Test func unmatchedRequestFallsBackToFullScope() {
  #expect(PlannerActionScope.select(for: "음 그거 해줘", mentionsProject: false) == .full)
}

@Test func mentionedProjectAddsProjectDomainWithoutKeywords() {
  let scope = PlannerActionScope.select(for: "피티 어디까지 했지", mentionsProject: true)
  #expect(scope.domains.contains(.project))
  #expect(scope.actions.contains(.getRememberedProjectStatus))
}

@Test func unscopedDiagnosticsStayAvailableInEveryScope() {
  let scope = PlannerActionScope(domains: [.browser])
  #expect(scope.actions.contains(.getCodingAgentStatus))
  #expect(scope.actions.contains(.getRemoteControlStatus))
  #expect(scope.actions.contains(.browserSearch))
  #expect(!scope.actions.contains(.openProject))
}

@Test func scopedSchemaEnumMatchesScopeActions() throws {
  let scope = PlannerActionScope(domains: [.server])
  let schema = AgentPlanner.schema(for: scope.actions)
  let steps = try #require((schema["properties"] as? [String: Any])?["steps"] as? [String: Any])
  let item = try #require(steps["items"] as? [String: Any])
  let action = try #require((item["properties"] as? [String: Any])?["action"] as? [String: Any])
  let values = try #require(action["enum"] as? [String])
  #expect(values.contains("get_docker_logs"))
  #expect(!values.contains("browser_search"))
  #expect(!values.contains("answer"))
}
