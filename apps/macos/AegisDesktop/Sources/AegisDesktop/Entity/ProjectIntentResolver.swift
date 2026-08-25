enum ProjectIntentResolver {
  static func plan(for request: String, repository: MemoryRepository) -> AgentPlan? {
    guard !hasExplicitDockerContext(request),
      let project = ProjectEntityResolver.resolve(in: request, repository: repository) else { return nil }
    let text = request.lowercased()
    let editor = CodeEditorResolver.resolve(for: request, repository: repository)
    if isWorkStatusQuestion(text) {
      let instruction = """
      현재 진행 중인 작업을 읽기 전용으로 분석해 주세요. 최근 커밋만 요약하지 말고 현재 Git diff와 변경 파일의 실제 코드 내용을 우선 확인하세요. 응답은 '확실한 사실', '추정', '근거', '한계'를 구분하고, 근거가 부족하면 작업 목적을 단정하지 마세요.
      """
      return AgentPlan(step: AgentStep(action: .analyzeProjectWithCodingAgent,
        content: instruction, project: project.name, codingMode: .readOnlyAnalysis))
    }
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

  static func isWorkStatusQuestion(_ text: String) -> Bool {
    let asksWhat = ["무슨", "뭐", "어떤", "알려", "확인", "내용"].contains(where: text.contains)
    let asksWork = ["작업 중", "작업중", "작업하고", "작업 내용", "진행 중", "진행중"]
      .contains(where: text.contains)
    return asksWhat && asksWork
  }
}
