import Foundation

enum CodingContinuationResolution: Equatable {
  case write(CodingContinuationIntent)
  case explain(CodingFindingContext)
  case inspectMore(CodingFindingContext)
  case findAnother(CodingFindingContext)
  case clarify
  case forget
}

struct CodingContinuationIntent: Equatable {
  let finding: CodingFindingContext
  let requestedMode: CodingTaskMode
  let goal: String

  var plan: AgentPlan {
    let proposal = AgentStep(action: .proposeCodingTask, content: goal,
      project: finding.projectName, codingMode: .workspaceWrite)
    let execute = AgentStep(action: .executeCodingTask, dependency: .requiresPreviousSuccess,
      content: goal, project: finding.projectName, codingMode: .workspaceWrite)
    return AgentPlan(steps: [proposal, execute])
  }
}

enum CodingContinuationIntentResolver {
  private static let references = ["방금 찾은", "그 문제", "그거", "아까 찾은", "그 개선점",
    "그 부분", "방금 말한", "그럼 수정", "좀 더", "관련 코드"]
  private static let writes = ["고쳐", "고치자", "수정해", "수정해줘", "수정하자", "실제로 고쳐",
    "반영해", "반영하자"]
  private static let continues = ["이어서 진행", "계속 진행", "계속해", "계속 해", "마저 해",
    "마저해", "이어가", "이어 가", "작업 추가해", "작업 추가 시켜"]

  static func isPotentialFollowUp(_ request: String) -> Bool {
    let text = request.lowercased()
    return references.contains(where: text.contains) || continues.contains(where: text.contains)
  }

  static func requestsMutation(_ request: String) -> Bool {
    let text = request.lowercased()
    return writes.contains(where: text.contains) || continues.contains(where: text.contains)
  }

  static func resolve(_ request: String, findings: [CodingFindingContext],
                      explicitProject: ProjectEntity? = nil) -> CodingContinuationResolution? {
    let text = request.lowercased()
    if ["다른 개선점", "다른 문제", "그건 됐고 다른"].contains(where: text.contains),
      let finding = explicitProject.flatMap({ project in
        findings.last { $0.projectId == project.name.lowercased() }
      }) ?? findings.last {
      return .findAnother(finding)
    }
    if ["이전 개선점 잊어", "방금 찾은 거 무시", "그건 됐고"].contains(where: text.contains) {
      return .forget
    }
    if continues.contains(where: text.contains) {
      let candidates = explicitProject.map { project in
        findings.filter { $0.projectId == project.name.lowercased() }
      } ?? findings
      guard !candidates.isEmpty else { return nil }
      guard Set(candidates.map(\.projectId)).count == 1, let finding = candidates.last else {
        return .clarify
      }
      let goal = "현재 분석된 작업을 안전한 범위에서 이어서 구현해 주세요. \(finding.recommendation)"
      return .write(.init(finding: finding, requestedMode: .workspaceWrite,
        goal: String(goal.prefix(1_000))))
    }
    guard references.contains(where: text.contains) else { return nil }
    let candidates = explicitProject.map { project in
      findings.filter { $0.projectId == project.name.lowercased() }
    } ?? findings
    guard !candidates.isEmpty else { return nil }
    guard Set(candidates.map(\.projectId)).count == 1, let finding = candidates.last else {
      return .clarify
    }
    if writes.contains(where: text.contains) {
      return .write(.init(finding: finding, requestedMode: .workspaceWrite,
        goal: String(request.prefix(1_000))))
    }
    if text.contains("설명") { return .explain(finding) }
    if text.contains("더 봐") || text.contains("관련 코드") { return .inspectMore(finding) }
    return nil
  }
}
