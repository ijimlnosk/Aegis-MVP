import Foundation

enum AgentPlannerError: LocalizedError {
  case invalidPlan([String])

  var errorDescription: String? {
    switch self { case .invalidPlan(let errors): "행동 계획이 올바르지 않습니다: \(errors.joined(separator: ", "))" }
  }
}

enum AgentPlanner {
  static func plan(for request: String, memory: MemoryContext) async throws -> AgentPlan {
    if let deterministic = MultiStepIntentParser.parse(memory.request) { return deterministic }
    if let serverPlan = ServerIntentParser.parse(memory.request) { return AgentPlan(step: serverPlan) }
    if let project = memory.project, memory.request.contains("열"),
       ["상태", "status"].contains(where: memory.request.lowercased().contains) {
      return AgentPlan(steps: [
        AgentStep(action: .openApplication, application: "Visual Studio Code", project: project.key),
        AgentStep(action: .getRememberedProjectStatus, dependency: .requiresPreviousSuccess, project: project.key),
      ])
    }
    if let project = memory.project,
       ["상태", "status"].contains(where: memory.request.lowercased().contains) {
      return AgentPlan(step: AgentStep(action: .getRememberedProjectStatus, project: project.key))
    }
    let content = plannerContent(request: memory.request, memories: memory.records)
    let generated = try await Ollama.structured(system: AgentPlannerPrompt.system, content: content, schema: schema)
    let first = PlanDependencyNormalizer.normalize(generated)
    let firstErrors = AgentPlanValidator.errors(in: first, for: request)
    if firstErrors.isEmpty { return MemoryRetriever.applyBrowserPreference(to: first, request: request, context: memory) }
    let retried = try await Ollama.structured(
      system: AgentPlannerPrompt.system + "\n이전 계획이 유효하지 않았다. 필수 필드와 원래 요청 의도를 확인해 한 번만 수정한다.",
      content: content + "\n\n이전 계획 오류: \(firstErrors.joined(separator: ", "))", schema: schema)
    let retry = PlanDependencyNormalizer.normalize(retried)
    let retryErrors = AgentPlanValidator.errors(in: retry, for: request)
    guard retryErrors.isEmpty else { throw AgentPlannerError.invalidPlan(retryErrors) }
    return MemoryRetriever.applyBrowserPreference(to: retry, request: request, context: memory)
  }

  private static func plannerContent(request: String, memories: [MemoryRecord]) -> String {
    "참고용 메모리 데이터:\n\(AgentPlannerPrompt.memoryData(memories))\n\n현재 요청: \(request)"
  }

  private static let schema: [String: Any] = [
    "type": "object",
    "properties": [
      "steps": ["type": "array", "minItems": 0, "maxItems": AgentPlan.maximumSteps,
        "items": stepSchema],
      "finalAnswer": ["type": "string"],
    ],
    "required": ["steps"],
  ]

  private static let stepSchema: [String: Any] = [
    "type": "object",
    "properties": [
      "action": ["type": "string", "enum": AgentAction.plannable.filter { $0 != .answer }.map(\.rawValue)],
      "dependency": ["type": "string", "enum": ["independent", "requires_previous_success"]],
      "recipient": ["type": "string"], "body": ["type": "string"],
      "application": ["type": "string"], "browser": ["type": "string"],
      "site": ["type": "string"], "query": ["type": "string"], "content": ["type": "string"],
      "project": ["type": "string"], "container": ["type": "string"],
      "lines": ["type": "integer", "minimum": 1, "maximum": 1000],
    ],
    "required": ["action", "dependency"],
  ]
}
