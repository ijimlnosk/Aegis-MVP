import Foundation

struct MemoryContext {
  let request: String
  let records: [MemoryRecord]
  let defaultBrowser: String?
  let project: MemoryRecord?
}

enum MemoryRetriever {
  static func relevant(to request: String, repository: MemoryRepository) -> MemoryContext {
    let all = (try? repository.records()) ?? []
    var resolved = request
    var relevant: [MemoryRecord] = []
    for memory in all where memory.type == .alias && contains(resolved, memory.key)
      && safeCanonicalValue(memory.value) {
      resolved = resolved.replacingOccurrences(of: memory.key, with: memory.value, options: .caseInsensitive)
      relevant.append(memory)
    }
    let project = all.first { memory in
      memory.type == .project && (contains(resolved, memory.key) || contains(resolved, memory.value))
    }
    if let project { relevant.append(project) }
    let browserRequest = ["검색", "열어", "접속", "search", "open"].contains(where: request.lowercased().contains)
    let preference = all.first { $0.type == .preference && $0.key == "default_browser" }
    if browserRequest, let preference { relevant.append(preference) }
    let tokens = request.lowercased().split(whereSeparator: { $0.isWhitespace }).filter { $0.count > 1 }
    relevant += all.filter { memory in
      memory.type == .fact && tokens.contains { memory.key.contains($0) || memory.value.lowercased().contains($0) }
    }
    return MemoryContext(request: resolved, records: unique(Array(relevant.prefix(8))),
      defaultBrowser: browserRequest ? preference?.value : nil, project: project)
  }

  static func applyBrowserPreference(to plan: AgentPlan, request: String, context: MemoryContext) -> AgentPlan {
    let steps = plan.steps.map { step -> AgentStep in
      guard step.action == .browserSearch else { return step }
      let browser = explicitBrowser(in: request) ?? context.defaultBrowser ?? step.browser
      return AgentStep(id: step.id, action: step.action, dependency: step.dependency,
        recipient: step.recipient, body: step.body, application: step.application,
        browser: browser, site: step.site, query: step.query, content: step.content,
        project: step.project, container: step.container, lines: step.lines)
    }
    return AgentPlan(steps: steps, finalAnswer: plan.finalAnswer)
  }

  private static func explicitBrowser(in request: String) -> String? {
    let names = ["Firefox", "Chrome", "Safari", "Arc", "Brave", "Edge"]
    let aliases = ["파이어폭스": "Firefox", "크롬": "Chrome", "사파리": "Safari"]
    if let name = names.first(where: { request.localizedCaseInsensitiveContains($0) }) { return name }
    return aliases.first(where: { request.contains($0.key) })?.value
  }

  private static func contains(_ text: String, _ value: String) -> Bool {
    text.range(of: value, options: .caseInsensitive) != nil
  }

  private static func safeCanonicalValue(_ value: String) -> Bool {
    value.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$", options: .regularExpression) != nil
  }

  private static func unique(_ records: [MemoryRecord]) -> [MemoryRecord] {
    var ids = Set<UUID>()
    return records.filter { ids.insert($0.id).inserted }
  }
}
