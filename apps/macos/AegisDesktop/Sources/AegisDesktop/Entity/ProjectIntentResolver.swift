enum ProjectIntentResolver {
  static func plan(for request: String, repository: MemoryRepository) -> AgentPlan? {
    guard !hasExplicitDockerContext(request),
      let project = ProjectEntityResolver.resolve(in: request, repository: repository) else { return nil }
    let text = request.lowercased()
    let editor = CodeEditorResolver.resolve(for: request, repository: repository)
    if ["상태", "status"].contains(where: text.contains),
       ["열", "켜", "시작", "작업"].contains(where: text.contains) {
      return AgentPlan(steps: [
        AgentStep(action: .openProject, application: editor, project: project.name),
        AgentStep(action: .getRememberedProjectStatus,
          dependency: .requiresPreviousSuccess, project: project.name),
      ])
    }
    if ["열", "켜", "시작", "작업"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .openProject,
        application: editor, project: project.name))
    }
    if text.contains("상태") || text.contains("status") {
      return AgentPlan(step: AgentStep(action: .getRememberedProjectStatus, project: project.name))
    }
    return nil
  }

  static func hasExplicitDockerContext(_ request: String) -> Bool {
    let text = request.lowercased()
    return ["docker", "도커", "컨테이너"].contains(where: text.contains)
  }
}
