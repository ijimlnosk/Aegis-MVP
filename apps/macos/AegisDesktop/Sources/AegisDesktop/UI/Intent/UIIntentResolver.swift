import Foundation

enum UIIntentResolver {
  static func plan(for request: String, repository: MemoryRepository) -> AgentPlan? {
    let lower = request.lowercased()
    if lower.contains("ui 제어 상태") || lower.contains("손쉬운 사용 상태") {
      return AgentPlan(step: AgentStep(action: .getUIControlStatus))
    }
    if lower.contains("vscode quick open 상태") || lower.contains("vscode quickopen 상태") {
      return AgentPlan(step: AgentStep(action: .getVSCodeQuickOpenStatus,
        application: "Visual Studio Code"))
    }
    if lower.contains("카카오톡"), lower.contains("보이는"),
      ["보내", "전송"].contains(where: lower.contains) {
      return AgentPlan(steps: [], finalAnswer: "화면 기반 메시지 전송은 지원하지 않습니다. 기존의 신뢰된 카카오톡 전송 기능을 사용해 주세요.")
    }
    let application = WindowResolver.requestedApplications(in: request).first
    let project = ProjectEntityResolver.resolve(in: request, repository: repository)?.name
    if let filename = filename(in: request), application == "Visual Studio Code",
      lower.contains("열어") { return VSCodeAdapter.quickOpenPlan(project: project, filename: filename) }
    if lower.contains("조작 가능한 ui") || lower.contains("조작 가능한 것") {
      return AgentPlan(step: AgentStep(action: .listUIElements,
        application: application, project: project))
    }
    if lower.contains("현재 창 닫") || lower.contains("창 닫아") {
      return AgentPlan(step: AgentStep(action: .closeWindow,
        application: application, project: project))
    }
    if let application, ["앞으로", "전환", "바꿔", "띄워", "창 열어"].contains(where: lower.contains) {
      let action: AgentAction = project != nil || lower.contains("창") ? .focusWindow
        : .activateApplication
      return AgentPlan(step: AgentStep(action: action, application: application,
        project: project))
    }
    if lower.contains("quick open") || lower.contains("검색창 열") {
      return AgentPlan(step: AgentStep(action: .pressKeyboardShortcut,
        application: application ?? "Visual Studio Code", shortcut: .quickOpen))
    }
    if let shortcut = shortcut(in: lower) {
      return AgentPlan(step: AgentStep(action: .pressKeyboardShortcut,
        application: application, shortcut: shortcut))
    }
    if let text = textInput(in: request) {
      return AgentPlan(step: AgentStep(action: .setUIText, application: application,
        content: text, uiLabel: inputLabel(in: lower), inputPurpose: inputPurpose(in: lower)))
    }
    if let label = buttonLabel(in: request) {
      return AgentPlan(step: AgentStep(action: .pressUIElement, application: application,
        uiLabel: label))
    }
    if lower.contains("아래로") || lower.contains("위로") {
      return AgentPlan(step: AgentStep(action: .scrollUI, application: application,
        scrollDirection: lower.contains("아래로") ? .down : .up))
    }
    return nil
  }

  private static func filename(in request: String) -> String? {
    guard let regex = try? NSRegularExpression(
      pattern: #"(?i)([A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,12})\s*(?:파일을?\s*)?열어"#),
      let match = regex.firstMatch(in: request, range: NSRange(request.startIndex..., in: request)),
      let range = Range(match.range(at: 1), in: request) else { return nil }
    return String(request[range])
  }

  private static func textInput(in request: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: #"(?:검색창|여기)에\s+(.+?)\s*(?:입력|써)해?$"#),
      let match = regex.firstMatch(in: request, range: NSRange(request.startIndex..., in: request)),
      let range = Range(match.range(at: 1), in: request) else { return nil }
    return String(request[range]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
  }

  private static func buttonLabel(in request: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: #"([^\s]+)\s+버튼\s*(?:눌러|클릭)"#),
      let match = regex.firstMatch(in: request, range: NSRange(request.startIndex..., in: request)),
      let range = Range(match.range(at: 1), in: request) else { return nil }
    let label = String(request[range]); return label == "저" ? nil : label
  }

  private static func shortcut(in lower: String) -> KeyboardShortcut? {
    if lower.contains("명령 팔레트") { return .commandPalette }
    if lower.contains("이전 탭") { return .previousTab }
    if lower.contains("다음 탭") { return .nextTab }
    if lower.contains("찾기") { return .find }
    return nil
  }

  private static func inputPurpose(in text: String) -> UIInputPurpose {
    if text.contains("검색") { return .navigationSearch }
    if text.contains("찾기") { return .find }
    if text.contains("필터") { return .filter }
    if text.contains("코드") || text.contains("편집기") { return .editorContent }
    if text.contains("메시지") || text.contains("채팅") { return .messageContent }
    if text.contains("터미널") { return .terminalInput }
    if text.contains("폼") { return .formContent }
    return .unknown
  }

  private static func inputLabel(in text: String) -> String {
    if text.contains("검색") { return "검색" }
    if text.contains("찾기") { return "찾기" }
    if text.contains("필터") { return "필터" }
    return "입력 필드"
  }
}
