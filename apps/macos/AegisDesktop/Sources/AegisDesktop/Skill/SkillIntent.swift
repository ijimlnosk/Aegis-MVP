import Foundation

enum SkillIntent {
  case teach(name: String, aliases: [String], plan: AgentPlan)
  case list
  case inspect(String)
  case forget(String)
  case rename(old: String, new: String)
}

enum SkillIntentParser {
  static func parse(_ request: String) -> SkillIntent? {
    let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
    if let values = captures("^(.+?)(?:을|를)\\s+(.+?)(?:으로|로)\\s*이름\\s*바꿔", text, 2) {
      return .rename(old: clean(values[0]), new: clean(values[1]))
    }
    if text.contains("Skill") || text.lowercased().contains("skill") {
      if text.contains("뭐 있어") || text.contains("목록") || text.contains("배운") { return .list }
      if let values = captures("^(.+?)\\s*[Ss]kill.*?(.+?)(?:으로|로)\\s*이름\\s*바꿔", text, 2) {
        return .rename(old: clean(values[0]), new: clean(values[1]))
      }
      if ["잊어", "지워", "삭제"].contains(where: text.contains),
         let name = captures("^(.+?)\\s*[Ss]kill", text, 1)?.first { return .forget(clean(name)) }
      if ["보여", "알려", "뭐야"].contains(where: text.contains),
         let name = captures("^(.+?)\\s*[Ss]kill", text, 1)?.first { return .inspect(clean(name)) }
    }
    guard let values = captures("^(?:앞으로\\s*)?(.+?)(?:이라고|라고)\\s*하면\\s*(.+)$", text, 2),
          let plan = taughtPlan(values[1]) else { return nil }
    return .teach(name: clean(values[0]), aliases: [], plan: plan)
  }

  private static func taughtPlan(_ body: String) -> AgentPlan? {
    if let plan = MultiStepIntentParser.parse(body) { return plan }
    if let step = ServerIntentParser.parse(body) { return AgentPlan(step: step) }
    if body.contains("VSCode") || body.localizedCaseInsensitiveContains("Visual Studio Code") {
      let project = body.split(separator: " ").first { $0.localizedCaseInsensitiveContains("PTFriends") }.map(String.init)
      guard let project, body.contains("상태") else { return nil }
      return AgentPlan(steps: [AgentStep(action: .openApplication, application: "Visual Studio Code", project: project),
        AgentStep(action: .getRememberedProjectStatus, dependency: .requiresPreviousSuccess, project: project)])
    }
    return nil
  }

  private static func captures(_ pattern: String, _ text: String, _ count: Int) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    let values = (1...count).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    return values.count == count ? values : nil
  }
  private static func clean(_ value: String) -> String {
    value.replacingOccurrences(of: "앞으로", with: "").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
  }
}
