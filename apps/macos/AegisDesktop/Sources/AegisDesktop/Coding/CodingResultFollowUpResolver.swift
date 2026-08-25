enum CodingResultFollowUpResolver {
  static func isDetailedLintQuestion(_ request: String) -> Bool {
    let text = request.lowercased().replacingOccurrences(of: " ", with: "")
    let lint = text.contains("lint") || text.contains("린트")
    let detail = ["각각", "어디", "위치", "왜", "원인", "상세", "목록", "어떤"]
      .contains(where: text.contains)
    return lint && detail
  }

  static func detailedLintPlan(request: String, project: String) -> AgentPlan {
    let instruction = "lint 원본 결과에 나온 각 경고의 파일과 줄, 규칙명, 발생 이유, 실제 위험도, 권장 수정 방향을 코드 기준으로 설명해 주세요. 코드는 수정하지 마세요. 사용자 요청: \(request)"
    return AgentPlan(steps: [
      AgentStep(action: .runProjectLint, project: project),
      AgentStep(action: .analyzeProjectWithCodingAgent, dependency: .requiresPreviousSuccess,
        content: instruction, project: project, codingMode: .readOnlyAnalysis),
    ])
  }

  static func isValidationFixRequest(_ request: String) -> Bool {
    let text = request.lowercased().replacingOccurrences(of: " ", with: "")
    let target = ["검증", "경고", "lint", "린트", "build", "빌드", "typecheck", "타입체크",
      "test", "테스트", "unsupported"].contains(where: text.contains)
    let mutation = ["추가하자", "추가해", "고치자", "고쳐", "수정하자", "수정해",
      "해결하자", "해결해", "지원하게", "되게해"].contains(where: text.contains)
    return target && mutation
  }

  static func fixPlan(request: String, project: String) -> AgentPlan {
    let goal = "최근 검증 결과를 근거로 다음 요청을 해결하고 해당 검증을 다시 실행해 주세요: \(request)"
    return AgentPlan(steps: [
      AgentStep(action: .proposeCodingTask, content: goal, project: project,
        codingMode: .workspaceWrite),
      AgentStep(action: .executeCodingTask, dependency: .requiresPreviousSuccess,
        content: goal, project: project, codingMode: .workspaceWrite),
    ])
  }

  static func isValidationQuestion(_ request: String) -> Bool {
    let text = request.lowercased().replacingOccurrences(of: " ", with: "")
    let validation = ["검증", "validation", "lint", "린트", "typecheck", "타입체크",
      "build", "빌드", "test", "테스트", "unsupported"].contains(where: text.contains)
    let detail = ["경고", "에러", "오류", "unsupported", "뭐", "무슨", "왜", "설명",
      "결과", "문제", "이유"].contains(where: text.contains)
    return validation && detail
  }
}
