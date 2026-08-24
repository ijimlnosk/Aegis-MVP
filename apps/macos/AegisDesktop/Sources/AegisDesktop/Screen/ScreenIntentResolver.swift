import Foundation

enum ScreenIntentResolver {
  static func plan(for request: String, repository: MemoryRepository) -> AgentPlan? {
    let text = request.lowercased()
    if ["열려 있는 창", "열린 창", "창들 뭐", "창 목록"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .listVisibleWindows))
    }
    let applications = WindowResolver.requestedApplications(in: request)
    if !applications.isEmpty,
      ["창", "화면", "봐", "비교", "찾아"].contains(where: text.contains) {
      let display = displayIndex(in: text)
      let project = ProjectEntityResolver.resolve(in: request, repository: repository)
      return AgentPlan(steps: applications.map {
        AgentStep(action: .inspectWindow, application: $0, project: project?.name,
          displayIndex: display)
      })
    }
    guard hasScreenIntent(text) else { return nil }
    if text.contains("화면 인식 상태") {
      return AgentPlan(step: AgentStep(action: .getScreenAwarenessStatus))
    }
    let display = displayIndex(in: text)
    let project = ProjectEntityResolver.resolve(in: request, repository: repository)
    let fullScreen = ScreenRequestPolicy.isExplicitFullScreen(text)
    let action: AgentAction = project == nil ? (fullScreen ? .inspectScreen : .inspectActiveWindow)
      : .inspectScreenWithProjectContext
    var steps = [AgentStep(action: action, project: project?.name, displayIndex: display)]
    if ProjectIntentResolver.hasExplicitDockerContext(request), let docker = ServerIntentParser.parse(request) {
      steps.append(docker)
    }
    return AgentPlan(steps: steps)
  }

  private static func hasScreenIntent(_ text: String) -> Bool {
    ["화면", "모니터", "현재 창", "활성 창", "vscode에 나온", "vscode 창",
     "이 에러", "뭘 하고", "뭐 하고"].contains(where: text.contains)
  }

  private static func displayIndex(in text: String) -> Int? {
    if text.contains("두 번째") || text.contains("2번 모니터") { return 2 }
    if text.contains("첫 번째") || text.contains("1번 모니터") { return 1 }
    guard let regex = try? NSRegularExpression(pattern: "([0-9]+)번\\s*모니터"),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let range = Range(match.range(at: 1), in: text) else { return nil }
    return Int(text[range])
  }
}
