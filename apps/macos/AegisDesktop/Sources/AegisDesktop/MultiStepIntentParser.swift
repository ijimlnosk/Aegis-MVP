import Foundation

enum MultiStepIntentParser {
  static func parse(_ request: String) -> AgentPlan? {
    if let plan = openAndBrowserSearch(request) { return plan }
    if let plan = browserAndClipboard(request) { return plan }
    let clauses = split(request)
    guard clauses.count > 1 else { return nil }
    var parsed: [AgentStep] = []
    for clause in clauses {
      if let step = ServerIntentParser.parse(clause) { parsed.append(step); continue }
      if let inherited = inheritedContainerMutation(clause, container: parsed.last?.container) {
        parsed.append(inherited); continue
      }
      return nil
    }
    guard parsed.count <= AgentPlan.maximumSteps else { return nil }
    var previous: AgentStep?
    let steps = parsed.map { step -> AgentStep in
      let dependency: StepDependency = needsPrevious(previous, step) ? .requiresPreviousSuccess : .independent
      previous = step
      return copy(step, dependency: dependency)
    }
    return AgentPlan(steps: steps)
  }

  private static func inheritedContainerMutation(_ text: String, container: String?) -> AgentStep? {
    guard let container else { return nil }
    if text.contains("재시작") { return AgentStep(action: .restartDockerContainer, container: container) }
    if text.contains("중지") || text.contains("내려") { return AgentStep(action: .stopDockerContainer, container: container) }
    if text.contains("시작") { return AgentStep(action: .startDockerContainer, container: container) }
    return nil
  }

  private static func split(_ request: String) -> [String] {
    request.replacingOccurrences(of: "한 다음", with: "|||")
      .replacingOccurrences(of: "그 다음", with: "|||")
      .replacingOccurrences(of: "그리고", with: "|||")
      .replacingOccurrences(of: "하고", with: "|||")
      .replacingOccurrences(of: " 보고 ", with: "|||")
      .split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func browserAndClipboard(_ request: String) -> AgentPlan? {
    guard request.contains("검색"), request.contains("클립보드") else { return nil }
    let browser = browserName(request)
    let site = request.localizedCaseInsensitiveContains("유튜브") ? "YouTube" : "Google"
    let query = searchQuery(request)
    guard !query.isEmpty else { return nil }
    return AgentPlan(steps: [AgentStep(action: .browserSearch, browser: browser, site: site, query: query),
      AgentStep(action: .getClipboard)])
  }

  private static func openAndBrowserSearch(_ request: String) -> AgentPlan? {
    guard request.contains("열고"), request.contains("검색"), let browser = browserName(request) else { return nil }
    let site = request.localizedCaseInsensitiveContains("유튜브") ? "YouTube" : "Google"
    let query = searchQuery(request)
    guard !query.isEmpty else { return nil }
    return AgentPlan(steps: [AgentStep(action: .openApplication, application: browser),
      AgentStep(action: .browserSearch, dependency: .requiresPreviousSuccess,
        browser: browser, site: site, query: query)])
  }

  private static func searchQuery(_ request: String) -> String {
    let start = request.range(of: "유튜브에서")?.upperBound
      ?? request.range(of: "youtube에서", options: .caseInsensitive)?.upperBound
    guard let end = request.range(of: "검색")?.lowerBound else { return "" }
    let raw = start.map { String(request[$0..<end]) } ?? String(request[..<end])
    return raw.replacingOccurrences(of: "Firefox로", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "Chrome으로", with: "", options: .caseInsensitive)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func browserName(_ text: String) -> String? {
    ["Firefox", "Chrome", "Safari", "Arc", "Brave", "Edge"]
      .first { text.localizedCaseInsensitiveContains($0) }
  }

  private static func needsPrevious(_ previous: AgentStep?, _ current: AgentStep) -> Bool {
    guard let previous else { return false }
    return previous.action.requiresApproval || current.action.requiresApproval || previous.action == .openApplication
  }

  private static func copy(_ step: AgentStep, dependency: StepDependency) -> AgentStep {
    AgentStep(id: step.id, action: step.action, dependency: dependency, recipient: step.recipient,
      body: step.body, application: step.application, browser: step.browser, site: step.site,
      query: step.query, content: step.content, project: step.project, container: step.container, lines: step.lines)
  }
}
