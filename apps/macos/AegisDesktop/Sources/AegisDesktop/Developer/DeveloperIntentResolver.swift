enum DeveloperIntentResolver {
  // Keywords that mean "tell me about a project" -- used only to decide whether an
  // unresolved project name deserves a clear "register it first" answer instead of
  // silently falling through to the LLM planner, which tends to guess a structurally
  // invalid plan (wrong action, missing/disallowed application, ...) for a project it
  // has no memory of. This never widens which projects can actually be touched --
  // ProjectEntityResolver's registered-only allowlist is unchanged.
  private static let statusIntentKeywords = ["어디까지", "최근 작업", "마지막으로", "뭐 했", "뭐하고",
    "뭐 하고", "뭐해", "뭐 해", "작업 끝", "마무리", "배포 준비", "전체 점검", "다 봐", "full check",
    "작업 시작", "작업하자", "상태", "문제", "health", "브랜치", "커밋", "변경", "diff"]
  private static let improvementIntentKeywords = ["추가하거나 변경하면 좋", "추가하거나 바꾸면 좋",
    "변경하면 좋", "고치면 좋", "개선 제안", "개선할 부분", "개선점", "문제점", "추천"]

  static func plan(for request: String, repository: MemoryRepository) -> AgentPlan? {
    let text = request.lowercased()
    guard ServerIntentParser.parse(request) == nil else { return nil }
    if ["오늘 뭐", "오늘 작업", "today's work"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .getTodayDevelopmentSummary))
    }
    guard !ProjectIntentResolver.hasExplicitDockerContext(request) else { return nil }
    if let locate = locateProjectPlan(request, text: text, repository: repository) { return locate }
    guard let project = ProjectEntityResolver.resolve(in: request, repository: repository) else {
      return unregisteredProjectGuidance(for: request, text: text, repository: repository)
    }
    if ["작업 끝", "마무리"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .endDevelopmentSession, project: project.name))
    }
    if ["어디까지", "최근 작업", "마지막으로", "뭐 했", "뭐하고", "뭐 하고", "뭐해", "뭐 해"].contains(where: text.contains) {
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
    if improvementIntentKeywords.contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .analyzeProjectWithCodingAgent,
        content: request, project: project.name, codingMode: .readOnlyAnalysis))
    }
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

  private static let locateKeywords = ["위치 찾아", "위치 알려", "어디있어", "어디 있어", "경로 찾아", "경로 알려"]

  // "<이름> 위치 찾아줘" -- if already registered, just answer with the known path;
  // otherwise search a bounded set of conventional project roots (ProjectDiscovery)
  // and, on a hit, remember it as a pending discovery so a follow-up "등록해" can
  // register it (see ProjectDiscoveryConfirmationParser) without retyping the path.
  private static func locateProjectPlan(_ request: String, text: String,
                                        repository: MemoryRepository) -> AgentPlan? {
    guard locateKeywords.contains(where: text.contains), let name = leadingProjectToken(in: request) else { return nil }
    if let known = ProjectEntityResolver.resolve(name: name, repository: repository), let path = known.path {
      return AgentPlan(steps: [], finalAnswer: "\"\(known.name)\"는 이미 등록되어 있습니다: \(path)")
    }
    return AgentPlan(step: AgentStep(action: .findProjectPath, content: name))
  }

  private static func unregisteredProjectGuidance(for request: String, text: String,
                                                   repository: MemoryRepository) -> AgentPlan? {
    guard statusIntentKeywords.contains(where: text.contains),
      let attempted = leadingProjectToken(in: request) else { return nil }
    let known = ProjectEntityResolver.knownProjects(repository: repository).map(\.name)
    let knownList = known.isEmpty ? "" : " (등록된 프로젝트: \(known.joined(separator: ", ")))"
    return AgentPlan(steps: [], finalAnswer: "\"\(attempted)\"는 등록된 프로젝트가 아닙니다.\(knownList) "
      + "등록하려면 \"\(attempted) 프로젝트 경로는 <절대경로>야\"라고 말씀해 주세요.")
  }

  private static func leadingProjectToken(in request: String) -> String? {
    let token = request.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    guard let first = token.first, first.isASCII, first.isLetter else { return nil }
    return String(token)
  }
}
