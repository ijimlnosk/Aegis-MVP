enum AutonomousDevelopmentIntentResolver {
  static func plan(for request: String, repository: MemoryRepository,
                   active: DevelopmentTaskCandidate?, recentWindow: ResolvedWindowTarget? = nil) -> AgentPlan? {
    let text = request.lowercased()
    if text.contains("자율 개발 상태") {
      return AgentPlan(step: AgentStep(action: .getAutonomousDevelopmentStatus))
    }
    if let active, isContinue(text) {
      if let explicit = ProjectEntityResolver.resolve(in: request, repository: repository),
        explicit.name.lowercased() != active.projectId { return nil }
      return AgentPlan(step: AgentStep(action: .executeDevelopmentTask,
        content: active.title, project: active.projectName))
    }
    guard isDiscovery(text), let project = resolveProject(request, repository, recentWindow) else { return nil }
    let screen = text.contains("현재") && (text.contains("화면") || text.contains("vscode") || text.contains("보이는"))
    let discover = AgentStep(action: .discoverDevelopmentTask,
      dependency: screen ? .requiresPreviousSuccess : .independent, content: request, project: project.name)
    let propose = AgentStep(action: .proposeDevelopmentTask,
      dependency: .requiresPreviousSuccess, content: request, project: project.name)
    if wantsExecution(text) {
      let execute = AgentStep(action: .executeDevelopmentTask,
        dependency: .requiresPreviousSuccess, content: request, project: project.name)
      return AgentPlan(steps: (screen ? [AgentStep(action: .inspectActiveWindow)] : []) + [discover, propose, execute])
    }
    return AgentPlan(steps: (screen ? [AgentStep(action: .inspectActiveWindow)] : []) + [discover, propose])
  }

  private static func isDiscovery(_ text: String) -> Bool {
    let task = ["할 만한", "먼저 할", "작은 개선", "작은 문제", "작업 하나", "문제 하나", "문제 중 하나"].contains(where: text.contains)
    return task && ["골라", "찾아", "처리", "해줘", "시작"].contains(where: text.contains)
  }
  private static func wantsExecution(_ text: String) -> Bool {
    ["고쳐줘", "처리해줘", "하나 해줘"].contains(where: text.contains)
  }
  private static func isContinue(_ text: String) -> Bool {
    ["해봐", "진행해", "좋아 해", "처리해", "수정해"].contains(where: text.contains)
  }

  private static func resolveProject(_ request: String, _ repository: MemoryRepository,
                                     _ recent: ResolvedWindowTarget?) -> ProjectEntity? {
    if let explicit = ProjectEntityResolver.resolve(in: request, repository: repository) { return explicit }
    guard let title = recent?.windowTitle else { return nil }
    return ProjectEntityResolver.knownProjects(repository: repository).first {
      title.localizedCaseInsensitiveContains($0.name)
        || $0.aliases.contains(where: title.localizedCaseInsensitiveContains)
    }
  }
}
