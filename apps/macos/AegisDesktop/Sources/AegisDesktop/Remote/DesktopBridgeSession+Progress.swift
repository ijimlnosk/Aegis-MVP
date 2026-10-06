import Foundation

/// Snapshots of the agent's chat and plan state reported to the remote client.
extension DesktopBridgeSession {
  func settledResult(after index: Int) -> DesktopBridgeResult {
    let messages = visibleMessages(after: index)
    let failed = messages.contains(where: { $0.hasPrefix("오류: ") })
    return DesktopBridgeResult(status: failed ? "failed" : "completed", messages: messages, pendingApproval: nil,
      failureCode: failed ? DesktopFailureClassifier.code(for: messages) : nil)
  }

  func visibleMessages(after index: Int) -> [String] {
    Array(agent.chat.messages.dropFirst(index).compactMap { message in
      switch message.role { case .assistant: message.content; case .error: "오류: \(message.content)"; default: nil }
    }.suffix(20))
  }

  func pendingApprovalCard() -> DesktopBridgeApprovalCard? {
    guard let pending = agent.pendingMacAction else { return nil }
    let goal = agent.chat.messages.first(where: { $0.id == pending.id })?.content ?? pending.detail
    return DesktopBridgeApprovalCard(id: pending.id.uuidString, title: pending.title,
      goal: goal, risk: pending.kind,
      scope: pending.arguments["project"] ?? pending.arguments["container"] ?? "AegisDesktop")
  }

  func currentStep() -> (index: Int, total: Int, action: AgentAction)? {
    guard let executor = agent.planExecutor else { return nil }
    let steps = executor.state.plan.steps
    let running = steps.firstIndex { executor.state.outcomes[$0.id] == .running }
    let index = running ?? min(executor.state.index, max(steps.count - 1, 0))
    guard steps.indices.contains(index) else { return nil }
    return (index + 1, steps.count, steps[index].action)
  }

  func bridgeProgress(phase: String, message: String,
                              step: (index: Int, total: Int, action: AgentAction)?,
                              startedAt: Date, cancellable: Bool) -> DesktopBridgeProgress {
    DesktopBridgeProgress(phase: phase, message: message, currentStep: step?.index,
      totalSteps: step?.total, cancellable: cancellable,
      startedAt: ISO8601DateFormatter().string(from: startedAt))
  }

  func phase(for action: AgentAction?) -> (String, String) {
    guard let value = action?.rawValue else { return ("planning", "요청을 이해하고 계획을 세우고 있습니다...") }
    if value.contains("validation") || value.contains("verify") { return ("validating", "변경사항을 검증하고 있습니다...") }
    if value.contains("coding_agent") || value == "analyze_project_with_coding_agent" {
      return ("analyzing", "Codex가 코드를 분석하고 있습니다...")
    }
    if value.contains("coding_task") || value.contains("development_task") {
      return ("coding", "Codex가 코드를 수정하고 있습니다...")
    }
    if value.contains("commit_plan") { return ("gitPlanning", "커밋 계획을 만들고 있습니다...") }
    if value.contains("commit") { return ("committing", "커밋을 생성하고 있습니다...") }
    if value.contains("push") { return ("pushing", "원격 저장소에 반영하고 있습니다...") }
    if value.contains("screen") || value.contains("window") { return ("screenAnalyzing", "화면을 확인하고 있습니다...") }
    if value.contains("server") || value.contains("docker") { return ("serverChecking", "서버 상태를 확인하고 있습니다...") }
    return ("running", "작업을 진행하고 있습니다...")
  }
}
