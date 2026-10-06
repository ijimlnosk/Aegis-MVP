import AegisWorkerProtocol
import Foundation

/// Durable command, worker lease, and write-authorization records for remote commands.
extension DesktopBridgeSession {
  func recoveredResult(commandId: String) -> DesktopBridgeResult? {
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

  func persist(_ commandId: String, _ request: String, _ result: DesktopBridgeResult) {
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

  func persistWorker(_ commandId: String, state: WorkerJobState) {
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

  func persistWriteAuthorization(commandId: String, approvalId: UUID) {
    guard agent.pendingMacAction?.kind == AgentAction.executeCodingTask.rawValue,
      let project = agent.pendingMacAction?.arguments["project"],
      let root = try? ProjectCommandPolicy.projectURL(project, repository: agent.memoryStore.repository),
      let snapshot = try? CodingGitInspector.snapshot(at: root),
      let request = jobs.record(commandId: commandId, sessionId: sessionID)?.request else { return }
    let changes = snapshot.entries.map { entry in
      let data = (try? Data(contentsOf: root.appendingPathComponent(entry.path))) ?? Data("missing".utf8)
      return WorkerBaselineEntry(path: entry.path,
        fingerprint: WorkerWriteAuthorization.digest(data))
    }
    let authorization = WorkerWriteAuthorization(commandId: commandId, sessionId: sessionID,
      approvalId: approvalId, request: request, projectRoot: root.path,
      baselineHead: snapshot.head, baselineBranch: snapshot.branch, baselineChanges: changes,
      maximumChangedFiles: CodingConfiguration.load().maximumChangedFiles,
      requiredValidations: ["typecheck", "lint", "test", "build"])
    try? workerAuthorizations?.issue(authorization)
  }
}
