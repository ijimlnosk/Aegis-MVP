import Foundation
import Testing
@testable import AegisDesktop

@Test func codexPlannerDefaultsOnAndHasExplicitKillSwitch() {
  #expect(CodexPlannerConfiguration.enabled(environment: [:]))
  #expect(!CodexPlannerConfiguration.enabled(environment: ["AEGIS_CODEX_PLANNER_ENABLED": "false"]))
}

@Test func codexPlannerIsEphemeralReadOnlyAndIgnoresUserConfiguration() {
  let planner = CodexPlanner(executable: URL(fileURLWithPath: "/missing"))
  let arguments = planner.arguments(prompt: "plan", schemaURL: URL(fileURLWithPath: "/tmp/schema"),
    resultURL: URL(fileURLWithPath: "/tmp/result"))
  #expect(arguments.contains("--ephemeral"))
  #expect(arguments.contains("--ignore-user-config"))
  #expect(arguments.contains("read-only"))
  #expect(!arguments.contains("workspace-write"))
  #expect(!arguments.contains("danger-full-access"))
}

@Test func unavailableCodexPlannerFailsBeforeCreatingAPlan() async {
  let planner = CodexPlanner(executable: URL(fileURLWithPath: "/missing/codex"))
  await #expect(throws: CodexPlannerError.self) {
    _ = try await planner.plan(system: "policy", content: "request", schema: AgentPlanner.schema)
  }
}
