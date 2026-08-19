import Foundation

enum ServerIntentParser {
  static func parse(_ request: String) -> AgentStep? {
    let text = request.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if let plan = containerMutation(text) { return plan }
    if text.contains("로그"), let container = value(before: "로그", in: text) {
      return plan(.getDockerLogs, container: container)
    }
    if text.contains("docker") || text.contains("도커") {
      if ["보여", "목록", "뭐", "확인"].contains(where: text.contains) {
        return plan(.getDockerContainers)
      }
    }
    if text.contains("프로젝트"), text.contains("상태") {
      let project = text.split(separator: " ").first.map(String.init) ?? "sol-server"
      return plan(.getServerProjectStatus, project: project)
    }
    if (text.contains("sol-server") || text.contains("서버")),
       ["상태", "어때", "확인"].contains(where: text.contains) {
      return plan(.getServerStatus)
    }
    return nil
  }

  private static func containerMutation(_ text: String) -> AgentStep? {
    let operations = [("다시 올려", "restart"), ("재시작", "restart"), ("중지", "stop"),
      ("내려", "stop"), ("올려", "start"), ("시작", "start")]
    for (word, action) in operations where text.contains(word) {
      guard let container = value(before: word, in: text) else { return nil }
      let actions: [String: AgentAction] = ["start": .startDockerContainer, "stop": .stopDockerContainer, "restart": .restartDockerContainer]
      guard let plannedAction = actions[action] else { return nil }
      return plan(plannedAction, container: container)
    }
    return nil
  }

  private static func value(before marker: String, in text: String) -> String? {
    guard let range = text.range(of: marker) else { return nil }
    let ignored = ["서버", "docker", "도커", "컨테이너", "를", "을"]
    let words = text[..<range.lowerBound].split(separator: " ").map(String.init)
      .filter { !ignored.contains($0) }
    guard let value = words.last, value.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$", options: .regularExpression) != nil else {
      return nil
    }
    return value
  }

  private static func plan(_ action: AgentAction, project: String? = nil, container: String? = nil) -> AgentStep {
    AgentStep(action: action, project: project, container: container)
  }
}
