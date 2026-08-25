import Foundation

enum PlanExecutionFormatter {
  static func format(_ summary: PlanExecutionSummary, plan: AgentPlan,
                     request: String) -> String? {
    if summary.status == .succeeded { return plan.finalAnswer }
    if summary.status == .cancelled {
      if let coding = plan.steps.first(where: { $0.action == .executeCodingTask }) {
        return "\(coding.project ?? "프로젝트") 코드 수정은 승인되지 않아 실행하지 않았습니다."
      }
      return "요청한 작업을 실행하지 않았습니다."
    }
    // Coding tools already surface their bounded result, changed files, and validation.
    // Repeating the failed step result here produces a duplicate mobile error card.
    if plan.steps.contains(where: { $0.action == .executeCodingTask }) { return nil }
    if let filename = plan.steps.last(where: { $0.shortcut == .confirm })?.content {
      let focused = summary.succeededSteps.contains { $0.action == .focusWindow }
      let reason = summary.failedSteps.first.flatMap { summary.results[$0.id] }
      let prefix = focused ? "대상 VSCode 창으로 전환했지만, " : ""
      return "\(prefix)\(reason.map { "\($0) " } ?? "")\(filename)은 열지 못했습니다."
    }
    let reason = summary.failedSteps.first.flatMap { summary.results[$0.id] }
      ?? "필수 실행 단계가 완료되지 않았습니다."
    return summary.status == .partiallySucceeded
      ? "일부 단계는 완료했지만 요청한 작업은 완료하지 못했습니다. \(reason)"
      : "요청한 작업을 완료하지 못했습니다. \(reason)"
  }
}
