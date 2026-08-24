import Foundation

extension AegisAgent {
  func runAutonomousDevelopmentTool(_ step: AgentStep, request: String) {
    let configuration = AutonomousDevelopmentConfiguration.load()
    if step.action == .getAutonomousDevelopmentStatus {
      Task {
        let text = await autonomousDevelopment.status(configuration: configuration)
        finishReadTool(text, action: step.action.rawValue, request: request)
      }
      return
    }
    if step.action == .proposeDevelopmentTask {
      guard let candidate = activeDevelopmentCandidate else {
        failCurrentStep(AutonomousDevelopmentError.noCandidate.localizedDescription); return
      }
      let executable = DevelopmentTaskPolicy.isExecutable(candidate, configuration: configuration)
      let proposal = AutonomousDevelopmentFormatter.proposal(candidate, executable: executable)
      speak(proposal)
      completeCurrentStep(succeeded: true,
        result: proposal)
      return
    }
    if step.action == .rankDevelopmentCandidates {
      guard let candidate = activeDevelopmentCandidate else {
        failCurrentStep(AutonomousDevelopmentError.noCandidate.localizedDescription); return
      }
      finishReadTool(AutonomousDevelopmentFormatter.proposal(candidate, executable: true),
        action: step.action.rawValue, request: request, target: candidate.projectName)
      return
    }
    if step.action == .verifyDevelopmentTask {
      Task {
        let text = await autonomousDevelopment.status(configuration: configuration)
        finishReadTool(text, action: step.action.rawValue, request: request)
      }
      return
    }
    if step.action == .repairDevelopmentTask {
      failCurrentStep("복구는 동일 승인 범위에서 첫 검증 실패 후 최대 1회만 자동 수행됩니다.")
      return
    }
    guard let project = step.project else { failCurrentStep("신뢰된 프로젝트가 필요합니다."); return }
    busy = true
    Task {
      do {
        let root = try ProjectCommandPolicy.projectURL(project, repository: memoryStore.repository)
        let provider = codingProviders.codex
        if step.action == .discoverDevelopmentTask {
          let candidate = try await autonomousDevelopment.discover(project: project, root: root,
            request: request, provider: provider, coding: codingCoordinator,
            repository: memoryStore.repository, configuration: configuration,
            untrustedEvidence: planExecutor.map { Array($0.state.results.values.suffix(1)) } ?? [])
          activeDevelopmentCandidate = candidate; busy = false
          try? developmentSessions.record(project: project,
            action: "autonomous:candidate:\(candidate.title)")
          completeCurrentStep(succeeded: true,
            result: AutonomousDevelopmentFormatter.proposal(candidate,
              executable: DevelopmentTaskPolicy.isExecutable(candidate, configuration: configuration)))
          return
        }
        guard step.action == .executeDevelopmentTask,
          let candidate = activeDevelopmentCandidate, candidate.projectId == project.lowercased() else {
          throw AutonomousDevelopmentError.staleCandidate
        }
        let result = try await autonomousDevelopment.execute(candidate, root: root,
          provider: provider, coding: codingCoordinator, repository: memoryStore.repository,
          configuration: configuration)
        busy = false
        let formatted = AutonomousDevelopmentResultFormatter.format(result)
        recordAutonomousHistory(result)
        activeDevelopmentCandidate = nil
        speak(formatted, role: [.succeeded, .succeededWithWarnings].contains(result.status) ? .assistant : .error)
        completeCurrentStep(succeeded: [.succeeded, .succeededWithWarnings].contains(result.status),
          result: formatted)
      } catch {
        busy = false; failCurrentStep(error.localizedDescription)
      }
    }
  }

  private func recordAutonomousHistory(_ result: AutonomousDevelopmentResult) {
    let validation = result.validation.map { "\($0.check.rawValue):\($0.status.rawValue)" }.joined(separator: ",")
    let history = AutonomousDevelopmentHistory(candidateId: result.candidate.id,
      projectId: result.candidate.projectId, category: result.candidate.category,
      title: result.candidate.title, outcome: result.status, provider: result.provider,
      changedFileCount: result.changedFiles.count, validationSummary: validation,
      repairAttempted: result.repairAttempted, timestamp: .now)
    if let data = try? JSONEncoder().encode(history), let value = String(data: data, encoding: .utf8) {
      _ = try? memoryStore.repository.save(MemoryRecord(type: .actionHistory,
        key: "autonomous:\(result.candidate.id.uuidString)", value: value, source: "aegis"))
    }
    memoryStore.recordAction(request: result.candidate.title, action: "autonomous_development",
      target: result.candidate.projectName,
      result: "\(result.status.rawValue); files=\(result.changedFiles.count); \(validation)",
      succeeded: [.succeeded, .succeededWithWarnings].contains(result.status))
    try? developmentSessions.record(project: result.candidate.projectName,
      action: "autonomous:\(result.status.rawValue):\(result.candidate.title)")
  }
}
