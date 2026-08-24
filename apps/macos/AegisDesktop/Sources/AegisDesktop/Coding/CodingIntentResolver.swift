enum CodingIntentResolver {
  private static let readOnlyPhrases = ["수정하지 말고", "수정하지말고", "코드 수정은 하지 말고",
    "코드 수정은 하지말고", "변경하지 말고", "변경하지말고", "건드리지 말고", "건드리지말고",
    "읽기만 해", "분석만 해", "리뷰만 해", "개선점만 찾아줘", "개선할 부분 하나만 찾아줘",
    "문제점만 찾아줘"]

  static func explicitReadOnlyPlan(for request: String, repository: MemoryRepository,
                                   recentWindow: ResolvedWindowTarget? = nil) -> AgentPlan? {
    let text = request.lowercased()
    guard readOnlyPhrases.contains(where: text.contains),
      let project = resolveProject(request, repository, recentWindow) else { return nil }
    return readOnlyPlan(request: request, project: project)
  }

  static func plan(for request: String, repository: MemoryRepository,
                   recentWindow: ResolvedWindowTarget? = nil) -> AgentPlan? {
    let text = request.lowercased()
    if text.contains("코딩 에이전트 최근 실행 진단") {
      return AgentPlan(step: AgentStep(action: .getCodingAgentRecentDiagnostics))
    }
    if ["코딩 에이전트 상태", "codex 상태", "코덱스 상태", "claude 상태", "클로드 상태"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .getCodingAgentStatus))
    }
    guard isCodingRequest(text), let project = resolveProject(request, repository, recentWindow) else {
      return nil
    }
    if readOnlyPhrases.contains(where: text.contains) { return readOnlyPlan(request: request, project: project) }
    if ["리뷰", "검토", "분석", "개선할 부분", "개선점", "문제점", "추가하거나 변경하면 좋",
        "추가하거나 바꾸면 좋", "변경하면 좋", "고치면 좋", "개선 제안", "추천"].contains(where: text.contains),
       !["고쳐", "수정", "정리", "리팩터"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .analyzeProjectWithCodingAgent,
        content: request, project: project.name, codingMode: .readOnlyAnalysis))
    }
    if ["롤백", "되돌려"].contains(where: text.contains) {
      return AgentPlan(step: AgentStep(action: .rollbackCodingTask, project: project.name))
    }
    let coding = AgentStep(action: .executeCodingTask,
      dependency: isScreenRequest(text) ? .requiresPreviousSuccess : .independent,
      content: request, project: project.name, codingMode: .workspaceWrite)
    if isScreenRequest(text) {
      return AgentPlan(steps: [AgentStep(action: .inspectActiveWindow), coding])
    }
    return AgentPlan(step: coding)
  }

  private static func readOnlyPlan(request: String, project: ProjectEntity) -> AgentPlan {
    AgentPlan(step: AgentStep(action: .analyzeProjectWithCodingAgent,
      content: request, project: project.name, codingMode: .readOnlyAnalysis))
  }

  private static func isCodingRequest(_ text: String) -> Bool {
    ["codex", "코덱스", "claude", "클로드", "코드", "typescript", "오류", "에러", "lint", "테스트",
     "리팩터", "고쳐", "수정", "롤백", "개선할 부분", "개선점", "문제점", "추가하거나 변경하면 좋",
     "추가하거나 바꾸면 좋", "변경하면 좋", "고치면 좋", "개선 제안", "추천"].contains(where: text.contains)
  }

  private static func isScreenRequest(_ text: String) -> Bool {
    (text.contains("현재") || text.contains("보이는") || text.contains("화면"))
      && (text.contains("vscode") || text.contains("vs code") || text.contains("창"))
  }

  private static func resolveProject(_ request: String, _ repository: MemoryRepository,
                                     _ recentWindow: ResolvedWindowTarget?) -> ProjectEntity? {
    if let explicit = ProjectEntityResolver.resolve(in: request, repository: repository) { return explicit }
    guard let title = recentWindow?.windowTitle else { return nil }
    return ProjectEntityResolver.knownProjects(repository: repository).first {
      title.localizedCaseInsensitiveContains($0.name)
        || $0.aliases.contains(where: title.localizedCaseInsensitiveContains)
    }
  }
}
