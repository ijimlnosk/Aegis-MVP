enum DeveloperIntentResolver {
  static func plan(for request: String, repository: MemoryRepository) -> AgentPlan? {
    let text = request.lowercased()
    if ["오늘 뭐", "오늘 작업", "today's work"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .getTodayDevelopmentSummary))
    }
    guard !ProjectIntentResolver.hasExplicitDockerContext(request),
      let project = ProjectEntityResolver.resolve(in: request, repository: repository) else { return nil }
    if ["작업 끝", "마무리"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .endDevelopmentSession, project: project.name))
    }
    if ["어디까지", "최근 작업", "마지막으로", "뭐 했"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .getDevelopmentRecap, project: project.name))
    }
    if ["배포 준비", "전체 점검", "다 봐", "full check"].contains(where: text.contains) {
      return validationPlan(project.name, request: request, repository: repository)
    }
    if ["작업 시작", "작업하자"].contains(where: text.contains) {
      let editor = CodeEditorResolver.resolve(for: request, repository: repository)
      return AgentPlan(steps: [AgentStep(action: .openProject, application: editor, project: project.name),
        AgentStep(action: .startDevelopmentSession, dependency: .requiresPreviousSuccess, project: project.name),
        AgentStep(action: .getProjectHealth, project: project.name)])
    }
    if ["상태", "문제", "health"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .getProjectHealth, project: project.name))
    }
    if text.contains("브랜치") { return AgentPlan(step: AgentStep(action: .getProjectBranch, project: project.name)) }
    if text.contains("커밋") { return AgentPlan(step: AgentStep(action: .getProjectRecentCommits, project: project.name)) }
    if text.contains("변경") || text.contains("diff") {
      return AgentPlan(step: AgentStep(action: .getProjectDiffSummary, project: project.name))
    }
    return nil
  }

  private static func validationPlan(_ project: String, request: String,
                                     repository: MemoryRepository) -> AgentPlan {
    let explicit = ProjectValidationCheck.allCases.filter { request.lowercased().contains($0.rawValue) }
    let profile = resolvedProfile(project: project, repository: repository)
    let checks = explicit.isEmpty ? profile?.allChecks ?? [] : explicit
    return AgentPlan(steps: checks
      .map { AgentStep(action: action(for: $0), project: project) }
      + [AgentStep(action: .assessProjectDeploymentReadiness, project: project)])
  }

  private static func resolvedProfile(project: String,
                                      repository: MemoryRepository) -> ProjectValidationProfile? {
    guard let url = try? ProjectCommandPolicy.projectURL(project, repository: repository),
      let package = try? PackageScriptTool.inspect(at: url) else { return nil }
    return ProjectValidationProfile.resolve(project: project, package: package, repository: repository)
  }

  private static func action(for check: ProjectValidationCheck) -> AgentAction {
    [.typecheck: .runProjectTypecheck, .lint: .runProjectLint,
     .test: .runProjectTests, .build: .runProjectBuild][check] ?? .unknown
  }
}
