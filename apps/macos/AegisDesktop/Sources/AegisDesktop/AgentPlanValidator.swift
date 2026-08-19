enum AgentPlanValidator {
  static func errors(in plan: AgentPlan, for request: String,
                     enforceRequestIntent: Bool = true) -> [String] {
    if plan.steps.isEmpty {
      return plan.finalAnswer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? [] : ["plan requires at least one step or finalAnswer"]
    }
    if plan.steps.count > AgentPlan.maximumSteps { return ["plan exceeds maximum step count"] }
    return plan.steps.enumerated().flatMap { index, step in
      var errors = errors(in: step, for: request,
        enforceRequestIntent: enforceRequestIntent).map { "step \(index + 1): \($0)" }
      if index == 0, step.dependency != .independent { errors.append("step 1 cannot depend on a previous step") }
      return errors
    }
  }

  static func errors(in step: AgentStep, for request: String,
                     enforceRequestIntent: Bool = true) -> [String] {
    switch step.action {
    case .kakaoMessage: missing([("recipient", step.recipient), ("body", step.body)])
    case .openApplication, .closeApplication: missing([("application", step.application)])
    case .openProject:
      missing([("project", step.project), ("application", step.application)])
        + (step.application.map(CodeEditorResolver.isAllowed) == true ? [] : ["application is not an allowed code editor"])
    case .browserSearch:
      enforceRequestIntent ? browserErrors(step, request: request) : missing([("site", step.site)])
    case .setClipboard: missing([("content", step.content)])
    case .getDockerLogs:
      missing([("container", step.container)]) + logLineErrors(step.lines)
    case .startDockerContainer, .stopDockerContainer, .restartDockerContainer:
      missing([("container", step.container)])
    case .getServerProjectStatus, .getRememberedProjectStatus: missing([("project", step.project)])
    case let action where action.isProjectAction: missing([("project", step.project)])
    case .inspectScreenWithProjectContext: missing([("project", step.project)])
    case .inspectWindow: missing([("application", step.application)])
    case .answer: ["answer is only allowed as plan.finalAnswer"]
    case .unknown: ["unknown action"]
    default: []
    }
  }

  private static func browserErrors(_ step: AgentStep, request: String) -> [String] {
    var errors = missing([("site", step.site)])
    let text = request.lowercased()
    let search = ["검색", "찾아", "search"].contains(where: text.contains)
    let open = ["열어", "접속", "켜줘", "open"].contains(where: text.contains)
    if search { errors += missing([("query", step.query)]) }
    else if open, step.query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
      errors.append("query must be empty for site-open intent")
    } else if !open { errors.append("browser intent is not present in the original request") }
    return errors
  }

  private static func missing(_ fields: [(String, String?)]) -> [String] {
    fields.compactMap { name, value in
      value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? nil : "missing \(name)"
    }
  }

  private static func logLineErrors(_ lines: Int?) -> [String] {
    guard let lines else { return [] }
    return (1...1_000).contains(lines) ? [] : ["lines must be between 1 and 1000"]
  }
}
