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
      if step.action == .pressKeyboardShortcut, step.shortcut == .confirm,
        !(index > 0 && plan.steps[index - 1].action == .setUIText
          && step.dependency == .requiresPreviousSuccess) {
        errors.append("step \(index + 1): confirm requires a dependent typed text step")
      }
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
    case .setClipboard:
      missing([("content", step.content)]) + (enforceRequestIntent
        && !hasClipboardIntent(request) ? ["clipboard intent is not present in the original request"] : [])
    case .getClipboard:
      enforceRequestIntent && !hasClipboardIntent(request)
        ? ["clipboard intent is not present in the original request"] : []
    case .getDockerLogs:
      missing([("container", step.container)]) + logLineErrors(step.lines)
    case .startDockerContainer, .stopDockerContainer, .restartDockerContainer:
      missing([("container", step.container)])
    case .getServerProjectStatus, .getRememberedProjectStatus: missing([("project", step.project)])
    case .findProjectPath: missing([("content", step.content)])
    case .analyzeProjectWithCodingAgent:
      missing([("project", step.project), ("content", step.content)])
        + (step.codingMode == .readOnlyAnalysis ? [] : ["read-only analysis requires readOnlyAnalysis mode"])
    case .proposeCodingTask, .executeCodingTask:
      missing([("project", step.project), ("content", step.content)])
        + (step.codingMode == nil ? ["missing codingMode"] : [])
        + (step.action == .executeCodingTask && step.codingMode != .workspaceWrite
          ? ["execute coding task requires workspaceWrite mode"] : [])
    case .rollbackCodingTask: missing([("project", step.project)])
    case .discoverDevelopmentTask, .proposeDevelopmentTask, .executeDevelopmentTask,
         .verifyDevelopmentTask, .repairDevelopmentTask:
      missing([("project", step.project), ("content", step.content)])
    case .rankDevelopmentCandidates, .getAutonomousDevelopmentStatus: []
    case .inspectGitDiff, .proposeCommitPlan, .createCommit, .getRemoteStatus,
         .proposePush, .pushCurrentBranch, .getCIStatus, .getPullRequestStatus,
         .getGitWorkflowStatus:
      missing([("project", step.project)])
    case let action where action.isProjectAction: missing([("project", step.project)])
    case .inspectScreenWithProjectContext: missing([("project", step.project)])
    case .inspectWindow: missing([("application", step.application)])
    case .activateApplication, .focusWindow: missing([("application", step.application)])
    case .setUIText, .appendUIText:
      missing([("content", step.content), ("uiLabel", step.uiLabel)])
        + (step.inputPurpose == nil ? ["missing inputPurpose"] : [])
        + (step.inputPurpose == .secureInput ? ["secure UI input is blocked"] : [])
        + (enforceRequestIntent && step.content.map({ !request.localizedCaseInsensitiveContains($0) }) == true
          ? ["UI text must come from the current user request"] : [])
    case .pressUIElement, .focusUIElement, .inspectUIElement, .selectMenuItem:
      missing([("uiLabel", step.uiLabel)])
        + (enforceRequestIntent && step.action == .pressUIElement
          && !["눌러", "클릭", "press"].contains(where: request.lowercased().contains)
          ? ["button press intent is not present in the original request"] : [])
    case .pressKeyboardShortcut:
      step.shortcut == nil ? ["missing shortcut"]
        : (step.shortcut == .closeWindow ? ["closeWindow must use close_window"] : [])
    case .scrollUI: step.scrollDirection == nil ? ["missing scrollDirection"] : []
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

  private static func hasClipboardIntent(_ request: String) -> Bool {
    let text = request.lowercased()
    return ["클립보드", "clipboard", "복사", "붙여넣"].contains(where: text.contains)
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
