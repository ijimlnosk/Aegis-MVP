import AegisWorkerProtocol
import Foundation

@MainActor
final class DesktopBridgeSession {
  let agent: AegisAgent
  /// True when commands run on the Mac window's own agent so both share in-progress context.
  let sharesDesktopAgent: Bool
  let sessionID: String
  let jobs: CommandJobStore
  let workerJobs: WorkerLeaseStore?
  let workerAuthorizations: WorkerAuthorizationStore?
  var approvedCommands: Set<String> = []
  private var commandResults: [String: DesktopBridgeResult] = [:]
  private var commandStartedAt: [String: Date] = [:]
  private var commandMessageIndex: [String: Int] = [:]
  var hasActiveCommand: Bool {
    commandStartedAt.keys.contains { id in
      guard let status = commandResults[id]?.status else { return true }
      return !["completed", "failed", "cancelled"].contains(status)
    }
  }

  init(sessionID: String, jobs: CommandJobStore = CommandJobStore(), sharedAgent: AegisAgent? = nil) {
    self.sessionID = sessionID
    self.jobs = jobs
    agent = sharedAgent ?? AegisAgent()
    sharesDesktopAgent = sharedAgent != nil
    workerJobs = try? WorkerLeaseStore(databaseURL: MemoryRepository.defaultDatabaseURL)
    workerAuthorizations = try? WorkerAuthorizationStore(databaseURL: MemoryRepository.defaultDatabaseURL)
    guard sharedAgent == nil else { return }
    agent.conversationSessionID = sessionID
    agent.gitWorkflowContext.sessionId = sessionID
  }

  func send(id: String, text: String) async -> DesktopBridgeResult {
    if let existing = commandResults[id] { return existing }
    if let recovered = recoveredResult(commandId: id) { return recovered }
    if sharesDesktopAgent, agent.busy || agent.planExecutor != nil || agent.pendingMacAction != nil {
      let busy = DesktopBridgeResult(status: "failed",
        messages: ["Mac에서 다른 작업이 진행 중이거나 승인을 기다리고 있습니다. 끝난 뒤 다시 요청해 주세요."],
        pendingApproval: nil, failureCode: "internalError")
      commandResults[id] = busy; persist(id, text, busy); return busy
    }
    commandStartedAt[id] = .now
    agent.remoteSessionID = sessionID
    agent.remoteCommandID = id
    agent.remoteRequestText = text
    let index = agent.chat.messages.count
    commandMessageIndex[id] = index
    persistWorker(id, state: .queued)
    persist(id, text, DesktopBridgeResult(status: "planning", messages: [], pendingApproval: nil,
      progress: bridgeProgress(phase: "planning", message: "요청을 이해하고 있습니다...",
        step: nil, startedAt: .now, cancellable: true)))
    agent.send(text)
    let result = await awaitResult(after: index)
    commandResults[id] = result
    persist(id, text, result)
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
    if commandStartedAt[commandId] == nil, let recovered = recoveredResult(commandId: commandId) {
      return recovered
    }
    let startedAt = commandStartedAt[commandId] ?? .now
    if agent.pendingMacAction != nil {
      let result = DesktopBridgeResult(status: "awaitingApproval", messages: [], pendingApproval: pendingApprovalCard(),
        progress: bridgeProgress(phase: "awaitingApproval", message: "승인을 기다리고 있습니다.",
          step: currentStep(), startedAt: startedAt, cancellable: false))
      persist(commandId, "", result)
      return result
    }
    if !agent.busy, agent.planExecutor == nil, let index = commandMessageIndex[commandId] {
      let result = settledResult(after: index)
      commandResults[commandId] = result
      persist(commandId, "", result)
      return result
    }
    let step = currentStep(), detail = phase(for: step?.action)
    let result = DesktopBridgeResult(status: agent.busy ? "running" : "planning", messages: [], pendingApproval: nil,
      progress: bridgeProgress(phase: detail.0, message: detail.1, step: step,
        startedAt: startedAt, cancellable: true))
    persist(commandId, "", result)
    return result
  }

  func approve(commandId: String, approvalId: UUID, accepted: Bool) async -> DesktopBridgeResult {
    let index = agent.chat.messages.count
    if accepted {
      persistWriteAuthorization(commandId: commandId, approvalId: approvalId)
      approvedCommands.insert(commandId); agent.approveChatAction(approvalId)
    }
    else { agent.rejectChatAction(approvalId) }
    let result = await awaitResult(after: index)
    commandResults[commandId] = result
    persist(commandId, "", result)
    return result
  }

  func cancel(commandId: String) -> DesktopBridgeResult {
    agent.cancelCurrentOperation()
    let result = DesktopBridgeResult(status: "cancelled", messages: ["작업을 취소했습니다."], pendingApproval: nil,
      failureCode: "commandCancelled")
    commandResults[commandId] = result
    persist(commandId, "", result)
    return result
  }

  private func awaitResult(after index: Int) async -> DesktopBridgeResult {
    for _ in 0..<3_000 {
      // The approval card is only reported once its chat message exists to supply the goal.
      if let pending = agent.pendingMacAction, agent.chat.messages.contains(where: { $0.id == pending.id }) {
        return DesktopBridgeResult(status: "awaitingApproval", messages: visibleMessages(after: index),
          pendingApproval: pendingApprovalCard())
      }
      if !agent.busy, agent.planExecutor == nil { return settledResult(after: index) }
      try? await Task.sleep(for: .milliseconds(20))
    }
    let step = currentStep(), detail = phase(for: step?.action)
    return DesktopBridgeResult(status: "running", messages: visibleMessages(after: index),
      pendingApproval: nil, progress: bridgeProgress(phase: detail.0,
        message: "작업이 계속 진행 중입니다. 완료 결과를 기다리고 있습니다.", step: step,
        startedAt: .now, cancellable: true))
  }
}
