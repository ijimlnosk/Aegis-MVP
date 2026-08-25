import Foundation

enum GitWorkflowContinuation {
  case plan(AgentPlan)
  case message(String)
}

enum GitWorkflowContinuationResolver {
  static func resolve(_ request: String, repository: MemoryRepository,
                      context: inout GitWorkflowContext, now: Date = .now) -> GitWorkflowContinuation? {
    let text = request.lowercased().replacingOccurrences(of: " ", with: "")
    if asksForValidation(text) {
      guard let report = context.lastValidationReport else {
        return .message("최근 커밋 검증 결과가 없습니다.")
      }
      return .message(GitValidationFormatter.format(report,
        failedCommit: !report.allowsCommit))
    }
    guard isContinuation(text) else { return nil }
    if context.plan == nil,
      ProjectEntityResolver.resolve(in: request, repository: repository) != nil { return nil }
    if context.expireIfNeeded(now: now) { return .message(GitWorkflowError.expiredCommitPlan.localizedDescription) }
    guard let plan = context.plan else { return .message(GitWorkflowError.noActiveCommitPlan.localizedDescription) }
    if context.state == .cancelled { return .message(GitWorkflowError.cancelledCommitPlan.localizedDescription) }
    if [.committed, .complete].contains(context.state) {
      return .message(GitWorkflowError.alreadyCommitted.localizedDescription)
    }
    guard ProjectEntityResolver.resolve(name: plan.projectId, repository: repository) != nil else {
      return .message("\(plan.projectId) 프로젝트 상태를 확인할 수 없습니다.")
    }
    if wantsReplan(text) {
      return .plan(AgentPlan(step: AgentStep(action: .proposeCommitPlan,
        content: "새 계획: \(request)", project: plan.projectId)))
    }
    let adjust = hasSelectionOrExclusion(text)
    let execute = wantsExecution(text)
    if adjust && !execute {
      return .plan(AgentPlan(step: AgentStep(action: .proposeCommitPlan,
        content: request, project: plan.projectId)))
    }
    let prepare = AgentStep(action: .proposeCommitPlan, content: request, project: plan.projectId)
    let commit = AgentStep(action: .createCommit, dependency: .requiresPreviousSuccess,
      content: "approved existing GitCommitPlan \(plan.id.uuidString)", project: plan.projectId)
    return .plan(AgentPlan(steps: [prepare, commit]))
  }
  private static func asksForValidation(_ text: String) -> Bool {
    text.contains("커밋검증") || text.contains("검증결과")
      || text.contains("왜커밋안") || text.contains("왜실패")
  }

  private static func isContinuation(_ text: String) -> Bool {
    if text == "해" || text == "진행해" { return true }
    return ["진행해", "커밋진행", "좋아해", "그대로해", "전부진행", "커밋해",
     "1번", "2번", "3번", "첫번째", "두번째", "세번째", "제외", "빼",
     "새로만들", "다시만들", "새계획", "다시계획"]
      .contains(where: text.contains)
  }
  private static func wantsReplan(_ text: String) -> Bool {
    ["새로만들", "다시만들", "새계획", "다시계획"].contains(where: text.contains)
  }
  private static func wantsExecution(_ text: String) -> Bool {
    ["진행", "해", "커밋"].contains(where: text.contains) && !text.contains("빼줘")
  }
  private static func hasSelectionOrExclusion(_ text: String) -> Bool {
    ["1번", "2번", "3번", "첫번째", "두번째", "세번째", "제외", "빼"].contains(where: text.contains)
  }
}
