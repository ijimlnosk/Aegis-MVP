import Foundation

enum AgentPlannerError: LocalizedError {
  case invalidPlan([String])

  var errorDescription: String? {
    switch self { case .invalidPlan(let errors): "행동 계획이 올바르지 않습니다: \(errors.joined(separator: ", "))" }
  }
}

enum AgentPlanner {
  static func plan(for request: String, memory: MemoryContext,
                   metrics: PlannerMetrics? = nil) async throws -> AgentPlan {
    if let diagnostics = AIBackendIntentResolver.plan(for: request) { return diagnostics }
    if let capability = CapabilityIntentResolver.plan(for: request) { return capability }
    if let deterministic = MultiStepIntentParser.parse(memory.request) { return deterministic }
    if let project = memory.project, memory.request.contains("열"),
       ["상태", "status"].contains(where: memory.request.lowercased().contains) {
      return AgentPlan(steps: [
        AgentStep(action: .openProject, application: "Visual Studio Code", project: project.key),
        AgentStep(action: .getRememberedProjectStatus, dependency: .requiresPreviousSuccess, project: project.key),
      ])
    }
    if let project = memory.project,
       ["상태", "status"].contains(where: memory.request.lowercased().contains) {
      return AgentPlan(step: AgentStep(action: .getRememberedProjectStatus, project: project.key))
    }
    if let serverPlan = ServerIntentParser.parse(memory.request) { return AgentPlan(step: serverPlan) }
    let content = plannerContent(request: memory.request, memories: memory.records)
    let scope = PlannerActionScope.select(for: memory.request, mentionsProject: memory.project != nil)
    let generated = try await generate(system: AgentPlannerPrompt.system(for: scope.domains),
      content: content, scope: scope, metrics: metrics)
    let first = PlanDependencyNormalizer.normalize(generated)
    let firstErrors = AgentPlanValidator.errors(in: first, for: request)
    if firstErrors.isEmpty { return MemoryRetriever.applyBrowserPreference(to: first, request: request, context: memory) }
    // The retry widens to every domain in case the narrowed scope hid the action the request needed.
    let retried = try await generate(
      system: AgentPlannerPrompt.system + "\n이전 계획이 유효하지 않았다. 필수 필드와 원래 요청 의도를 확인해 한 번만 수정한다.",
      content: content + "\n\n이전 계획 오류: \(firstErrors.joined(separator: ", "))",
      scope: .full, metrics: metrics)
    let retry = PlanDependencyNormalizer.normalize(retried)
    let retryErrors = AgentPlanValidator.errors(in: retry, for: request)
    guard retryErrors.isEmpty else { throw AgentPlannerError.invalidPlan(retryErrors) }
    return MemoryRetriever.applyBrowserPreference(to: retry, request: request, context: memory)
  }

  private static func generate(system: String, content: String, scope: PlannerActionScope,
                               metrics: PlannerMetrics?) async throws -> AgentPlan {
    let schema = schema(for: scope.actions)
    let timed = TimedPlannerCall(promptCharacters: system.count + content.count, scope: scope, metrics: metrics)
    if CodexPlannerConfiguration.isEnabled {
      do { return try await timed.run("codex") { try await CodexPlanner().plan(system: system, content: content, schema: schema) } }
      catch { /* Preserve the configured local planner as a bounded availability fallback. */ }
    }
    return try await timed.run("ollama") { try await Ollama.structured(system: system, content: content, schema: schema) }
  }

  private static func plannerContent(request: String, memories: [MemoryRecord]) -> String {
    "참고용 메모리 데이터:\n\(AgentPlannerPrompt.memoryData(memories))\n\n현재 요청: \(request)"
  }

  static let schema = schema(for: AgentAction.plannable)

  static func schema(for actions: [AgentAction]) -> [String: Any] {
    var step = stepSchema
    var properties = step["properties"] as? [String: Any] ?? [:]
    properties["action"] = ["type": "string", "enum": actions.filter { $0 != .answer }.map(\.rawValue)]
    step["properties"] = properties
    return [
      "type": "object",
      "properties": [
        "steps": ["type": "array", "minItems": 0, "maxItems": AgentPlan.maximumSteps, "items": step],
        "finalAnswer": ["type": "string"],
      ],
      "required": ["steps"],
    ]
  }

  private static let stepSchema: [String: Any] = [
    "type": "object",
    "properties": [
      "action": ["type": "string"],
      "dependency": ["type": "string", "enum": ["independent", "requires_previous_success"]],
      "recipient": ["type": "string"], "body": ["type": "string"],
      "application": ["type": "string"], "browser": ["type": "string"],
      "site": ["type": "string"], "query": ["type": "string"], "content": ["type": "string"],
      "project": ["type": "string"], "container": ["type": "string"],
      "lines": ["type": "integer", "minimum": 1, "maximum": 1000],
      "displayIndex": ["type": "integer", "minimum": 1, "maximum": 16],
      "uiLabel": ["type": "string"],
      "shortcut": ["type": "string", "enum": KeyboardShortcut.allCases.map(\.rawValue)],
      "scrollDirection": ["type": "string", "enum": ["up", "down", "left", "right"]],
      "inputPurpose": ["type": "string", "enum": ["navigationSearch", "commandSearch",
        "find", "filter", "editorContent", "messageContent", "formContent",
        "terminalInput", "secureInput", "unknown"]],
      "codingMode": ["type": "string", "enum": ["readOnlyAnalysis", "workspaceWrite"]],
    ],
    "required": ["action", "dependency"],
  ]
}
