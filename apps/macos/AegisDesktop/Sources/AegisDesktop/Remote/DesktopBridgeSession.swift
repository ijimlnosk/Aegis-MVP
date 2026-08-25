import AegisWorkerProtocol
import Foundation

@MainActor
final class DesktopBridgeSession {
  let agent = AegisAgent()
  private let sessionID: String
  private let jobs: CommandJobStore
  private let workerJobs: WorkerLeaseStore?
  private var approvedCommands: Set<String> = []
  private var commandResults: [String: DesktopBridgeResult] = [:]
  private var commandStartedAt: [String: Date] = [:]
  private var commandMessageIndex: [String: Int] = [:]
  var hasActiveCommand: Bool {
    commandStartedAt.keys.contains { id in
      guard let status = commandResults[id]?.status else { return true }
      return !["completed", "failed", "cancelled"].contains(status)
    }
  }

  init(sessionID: String, jobs: CommandJobStore = CommandJobStore()) {
    self.sessionID = sessionID
    self.jobs = jobs
    workerJobs = try? WorkerLeaseStore(databaseURL: MemoryRepository.defaultDatabaseURL)
    agent.conversationSessionID = sessionID
    agent.gitWorkflowContext.sessionId = sessionID
  }

  func send(id: String, text: String) async -> DesktopBridgeResult {
    if let existing = commandResults[id] { return existing }
    if let recovered = recoveredResult(commandId: id) { return recovered }
    commandStartedAt[id] = .now
    agent.remoteSessionID = sessionID
    agent.remoteCommandID = id
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
      let messages = visibleMessages(after: index)
      let failed = messages.contains(where: { $0.hasPrefix("오류: ") })
      let result = DesktopBridgeResult(status: failed ? "failed" : "completed",
        messages: messages, pendingApproval: nil,
        failureCode: failed ? DesktopFailureClassifier.code(for: messages) : nil)
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
    if accepted { approvedCommands.insert(commandId); agent.approveChatAction(approvalId) }
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

  private func recoveredResult(commandId: String) -> DesktopBridgeResult? {
    guard let record = jobs.record(commandId: commandId, sessionId: sessionID) else { return nil }
    if ["completed", "failed", "cancelled"].contains(record.result.status) { return record.result }
    if let recovered = CodexWorkerRunner.recover(sessionId: sessionID, commandId: commandId) {
      jobs.save(commandId: commandId, sessionId: sessionID, request: record.request, result: recovered)
      return recovered
    }
    if CodexWorkerRunner.hasPendingResult(sessionId: sessionID, commandId: commandId) {
      return DesktopBridgeResult(status: "running", messages: [], pendingApproval: nil,
        progress: DesktopBridgeProgress(phase: "analyzing",
          message: "worker에서 코드 분석을 계속하고 있습니다.", currentStep: nil,
          totalSteps: nil, cancellable: false, startedAt: ISO8601DateFormatter().string(from: .now)))
    }
    let interrupted = DesktopBridgeResult(status: "failed",
      messages: ["AegisDesktop이 재시작되어 이전 작업이 중단되었습니다. 같은 요청을 다시 실행해 주세요."],
      pendingApproval: nil, failureCode: "desktopRestarted")
    jobs.save(commandId: commandId, sessionId: sessionID, request: record.request, result: interrupted)
    return interrupted
  }

  private func persist(_ commandId: String, _ request: String, _ result: DesktopBridgeResult) {
    let original = request.isEmpty ? jobs.record(commandId: commandId, sessionId: sessionID)?.request ?? "" : request
    jobs.save(commandId: commandId, sessionId: sessionID, request: original, result: result)
    let state: WorkerJobState = switch result.status {
    case "completed": .completed
    case "failed": .failed
    case "cancelled": .cancelled
    case "awaitingApproval": .awaitingApproval
    default: .running
    }
    persistWorker(commandId, state: state)
  }

  private func persistWorker(_ commandId: String, state: WorkerJobState) {
    let steps = agent.planExecutor?.state.plan.steps ?? []
    let mutation = steps.isEmpty || steps.contains { $0.action.requiresApproval }
    let validates = steps.contains { step in
      [.runProjectTypecheck, .runProjectLint, .runProjectTests, .runProjectBuild,
       .verifyCodingTask, .executeCodingTask].contains(step.action)
    }
    let contract = WorkerJobContract(commandId: commandId, sessionId: sessionID,
      state: state, risk: mutation ? .mutation : .readOnly,
      approvalGranted: approvedCommands.contains(commandId), hasValidationPlan: validates,
      leaseExpiresAt: nil)
    try? workerJobs?.upsert(contract)
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
