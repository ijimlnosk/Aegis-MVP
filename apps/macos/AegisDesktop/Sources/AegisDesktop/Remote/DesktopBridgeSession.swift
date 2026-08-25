import Foundation

@MainActor
final class DesktopBridgeSession {
  let agent = AegisAgent()
  private var commandResults: [String: DesktopBridgeResult] = [:]
  private var commandStartedAt: [String: Date] = [:]
  private var commandMessageIndex: [String: Int] = [:]

  init(sessionID: String) {
    agent.conversationSessionID = sessionID
    agent.gitWorkflowContext.sessionId = sessionID
  }

  func send(id: String, text: String) async -> DesktopBridgeResult {
    if let existing = commandResults[id] { return existing }
    commandStartedAt[id] = .now
    let index = agent.chat.messages.count
    commandMessageIndex[id] = index
    agent.send(text)
    let result = await awaitResult(after: index)
    commandResults[id] = result
    return result
  }

  func progress(commandId: String) -> DesktopBridgeResult {
    // Approval responses are deliberately not authoritative snapshots. The mobile
    // client polls immediately after tapping approve, while the same approval call
    // may still be running validation/commit work. Returning the cached
    // `awaitingApproval` result here makes the card reappear even after approval.
    // Only terminal results are safe to cache; live paused/running state must be
    // derived from the current AegisAgent session.
    if let result = commandResults[commandId], ["completed", "failed", "cancelled"].contains(result.status) {
      return result
    }
    let startedAt = commandStartedAt[commandId] ?? .now
    if agent.pendingMacAction != nil {
      return DesktopBridgeResult(status: "awaitingApproval", messages: [], pendingApproval: pendingApprovalCard(),
        progress: bridgeProgress(phase: "awaitingApproval", message: "승인을 기다리고 있습니다.",
          step: currentStep(), startedAt: startedAt, cancellable: false))
    }
    if !agent.busy, agent.planExecutor == nil, let index = commandMessageIndex[commandId] {
      let messages = visibleMessages(after: index)
      let failed = messages.contains(where: { $0.hasPrefix("오류: ") })
      let result = DesktopBridgeResult(status: failed ? "failed" : "completed",
        messages: messages, pendingApproval: nil,
        failureCode: failed ? DesktopFailureClassifier.code(for: messages) : nil)
      commandResults[commandId] = result
      return result
    }
    let step = currentStep(), detail = phase(for: step?.action)
    return DesktopBridgeResult(status: agent.busy ? "running" : "planning", messages: [], pendingApproval: nil,
      progress: bridgeProgress(phase: detail.0, message: detail.1, step: step,
        startedAt: startedAt, cancellable: true))
  }

  func approve(commandId: String, approvalId: UUID, accepted: Bool) async -> DesktopBridgeResult {
    let index = agent.chat.messages.count
    if accepted { agent.approveChatAction(approvalId) } else { agent.rejectChatAction(approvalId) }
    let result = await awaitResult(after: index)
    commandResults[commandId] = result
    return result
  }

  func cancel(commandId: String) -> DesktopBridgeResult {
    agent.cancelCurrentOperation()
    let result = DesktopBridgeResult(status: "cancelled", messages: ["작업을 취소했습니다."], pendingApproval: nil,
      failureCode: "commandCancelled")
    commandResults[commandId] = result
    return result
  }

  private func awaitResult(after index: Int) async -> DesktopBridgeResult {
    for _ in 0..<3_000 {
      if let pending = agent.pendingMacAction,
         let message = agent.chat.messages.first(where: { $0.id == pending.id }) {
        return DesktopBridgeResult(status: "awaitingApproval", messages: visibleMessages(after: index),
          pendingApproval: DesktopBridgeApprovalCard(id: pending.id.uuidString, title: pending.title,
            goal: message.content, risk: pending.kind,
            scope: pending.arguments["project"] ?? pending.arguments["container"] ?? "AegisDesktop"))
      }
      if !agent.busy, agent.planExecutor == nil {
        let messages = visibleMessages(after: index)
        let failed = messages.contains(where: { $0.hasPrefix("오류: ") })
        return DesktopBridgeResult(status: failed ? "failed" : "completed", messages: messages, pendingApproval: nil,
                                   failureCode: failed ? DesktopFailureClassifier.code(for: messages) : nil)
      }
      try? await Task.sleep(for: .milliseconds(20))
    }
    let step = currentStep(), detail = phase(for: step?.action)
    return DesktopBridgeResult(status: "running", messages: visibleMessages(after: index),
      pendingApproval: nil, progress: bridgeProgress(phase: detail.0,
        message: "작업이 계속 진행 중입니다. 완료 결과를 기다리고 있습니다.", step: step,
        startedAt: .now, cancellable: true))
  }

  private func visibleMessages(after index: Int) -> [String] {
    Array(agent.chat.messages.dropFirst(index).compactMap { message in
      switch message.role { case .assistant: message.content; case .error: "오류: \(message.content)"; default: nil }
    }.suffix(20))
  }

  private func pendingApprovalCard() -> DesktopBridgeApprovalCard? {
    guard let pending = agent.pendingMacAction else { return nil }
    let goal = agent.chat.messages.first(where: { $0.id == pending.id })?.content ?? pending.detail
    return DesktopBridgeApprovalCard(id: pending.id.uuidString, title: pending.title,
      goal: goal, risk: pending.kind,
      scope: pending.arguments["project"] ?? pending.arguments["container"] ?? "AegisDesktop")
  }

  private func currentStep() -> (index: Int, total: Int, action: AgentAction)? {
    guard let executor = agent.planExecutor else { return nil }
    let steps = executor.state.plan.steps
    let running = steps.firstIndex { executor.state.outcomes[$0.id] == .running }
    let index = running ?? min(executor.state.index, max(steps.count - 1, 0))
    guard steps.indices.contains(index) else { return nil }
    return (index + 1, steps.count, steps[index].action)
  }

  private func bridgeProgress(phase: String, message: String,
                              step: (index: Int, total: Int, action: AgentAction)?,
                              startedAt: Date, cancellable: Bool) -> DesktopBridgeProgress {
    DesktopBridgeProgress(phase: phase, message: message, currentStep: step?.index,
      totalSteps: step?.total, cancellable: cancellable,
      startedAt: ISO8601DateFormatter().string(from: startedAt))
  }

  private func phase(for action: AgentAction?) -> (String, String) {
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
