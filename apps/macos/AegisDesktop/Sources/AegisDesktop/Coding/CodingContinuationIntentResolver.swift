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
  private static let writes = ["고쳐", "수정해", "수정해줘", "실제로 고쳐", "반영해"]

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
