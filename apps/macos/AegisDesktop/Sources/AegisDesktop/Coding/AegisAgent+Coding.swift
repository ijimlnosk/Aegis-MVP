import Foundation

extension AegisAgent {
  func runCodingTool(_ step: AgentStep, request: String) {
    if [.getCodingAgentStatus, .getCodingAgentRecentDiagnostics].contains(step.action) {
      busy = true
      Task {
        let selected = CodingAgentProviderResolver.resolve(request: request,
          project: step.project ?? "", repository: memoryStore.repository,
          configuration: codingProviders.configuration)
        let provider = codingProviders.provider(selected)
        let status = await codingCoordinator.status(provider: provider)
        busy = false
        let text: String
        if step.action == .getCodingAgentRecentDiagnostics {
          text = CodingTaskFormatter.recentDiagnostics(status)
        } else {
          text = CodingTaskFormatter.diagnostics(primary: status, fallback: nil)
        }
        finishReadTool(text, action: step.action.rawValue,
          request: request, target: "Codex")
      }
      return
    }
    let project = step.project ?? ""
    if step.action == .proposeCodingTask {
      do {
        let proposal = try CodingTaskProposal.make(project: project,
          request: step.content ?? request, finding: activeCodingContinuation,
          repository: memoryStore.repository)
        activeCodingTaskProposal = proposal; codingTaskProposalLifecycle = .proposed
        let detail = CodingFindingProposalFormatter.format(proposal)
        memoryStore.recordAction(request: request, action: step.action.rawValue,
          target: project, result: "proposal created", succeeded: true)
        speak(detail)
        completeCurrentStep(succeeded: true, result: detail)
      } catch { failCurrentStep(error.localizedDescription) }
      return
    }
    if [.reviewCodingTaskResult, .verifyCodingTask].contains(step.action) {
      busy = true
      Task {
        do {
          let root = try ProjectCommandPolicy.projectURL(project, repository: memoryStore.repository)
          let text: String
          if step.action == .verifyCodingTask {
            let values = await codingCoordinator.verify(project: project, root: root,
              repository: memoryStore.repository)
            text = values.map { "\($0.check.rawValue): \($0.status.rawValue) · \($0.summary)" }
              .joined(separator: "\n")
          } else {
            let selected = CodingAgentProviderResolver.resolve(request: request, project: project,
              repository: memoryStore.repository, configuration: codingProviders.configuration)
            text = CodingTaskFormatter.diagnostics(await codingCoordinator.status(
              provider: codingProviders.selected(selected)))
          }
          busy = false; finishReadTool(text, action: step.action.rawValue, request: request, target: project)
        } catch { busy = false; failCurrentStep(error.localizedDescription) }
      }
      return
    }
    busy = true
    let requestedMode = step.codingMode ?? .readOnlyAnalysis
    recordActivity(requestedMode == .readOnlyAnalysis
      ? "\(project) 코드를 읽기 전용으로 분석하고 있습니다..."
      : "\(project) 코딩 작업을 실행하고 있습니다...")
    codingTask = Task {
      do {
        let proposal = activeCodingTaskProposal.flatMap {
          $0.projectId == project.lowercased() ? $0 : nil
        }
        if requestedMode == .workspaceWrite, step.dependency == .requiresPreviousSuccess,
          proposal == nil { throw CodingTaskError.taskNotFound }
        if requestedMode == .workspaceWrite { codingTaskProposalLifecycle = .running }
        let root = try ProjectCommandPolicy.projectURL(project, repository: memoryStore.repository)
        guard FileManager.default.fileExists(atPath: root.appending(path: ".git").path) else {
          throw CodingTaskError.notGitRepository
        }
        if step.action == .rollbackCodingTask {
          let files = try await codingCoordinator.rollbackLast(projectRoot: root)
          busy = false; codingTask = nil
          let result = "\(project) 코딩 작업 변경을 되돌렸습니다.\n" + files.map { "- \($0)" }.joined(separator: "\n")
          try? developmentSessions.record(project: project, action: "rollback_coding_task")
          finishReadTool(result, action: step.action.rawValue, request: request, target: project)
          return
        }
        let mode = requestedMode
        let previousResults = planExecutor.map { Array($0.state.results.values) } ?? []
        var evidence = previousResults.prefix(3).map { String($0.prefix(2_000)) }
        let sourceFinding = activeCodingContinuation.flatMap {
          $0.projectId == project.lowercased() ? $0 : nil
        }
        if let sourceFinding { evidence.append(sourceFinding.boundedEvidence) }
        let task = CodingTask(project: project, projectRoot: root,
          request: proposal?.currentRequest ?? step.content ?? request, mode: mode,
          untrustedEvidence: evidence,
          sourceFindingId: proposal?.sourceFindingId ?? sourceFinding?.id,
          sourceFindingTitle: sourceFinding?.title)
        let selectedID = proposal?.provider ?? CodingAgentProviderResolver.resolve(
          request: step.content ?? request, project: project, repository: memoryStore.repository,
          configuration: codingProviders.configuration)
        let provider = codingProviders.selected(selectedID)
        var configuration = CodingConfiguration.load()
        if provider.identifier == .claude, let timeout = codingProviders.configuration.claudeTimeout {
          configuration = .init(timeout: timeout,
            maximumChangedFiles: configuration.maximumChangedFiles)
        }
        let result = try await codingCoordinator.run(task, provider: provider,
          configuration: configuration, repository: memoryStore.repository)
        recordActivity("코딩 에이전트 결과를 검증하고 있습니다...")
        if mode == .workspaceWrite { codingTaskProposalLifecycle = .verifying }
        busy = false; codingTask = nil
        try? developmentSessions.record(project: project,
          action: "coding:\(result.status.rawValue):\(result.changedFiles.joined(separator: ","))")
        let workStatus = ProjectIntentResolver.isWorkStatusQuestion(request.lowercased())
        let formatted = CodingTaskFormatter.format(result, project: project, workStatus: workStatus)
        if let finding = CodingFindingParser.parse(result: result) {
          codingFindings.removeAll { $0.projectId == finding.projectId }
          codingFindings.append(finding)
        }
        if mode == .workspaceWrite {
          codingTaskProposalLifecycle = [.succeeded, .succeededWithWarnings].contains(result.status)
            ? .succeeded : .failed
          activeCodingContinuation = nil; activeCodingTaskProposal = nil
        }
        memoryStore.recordAction(request: request, action: step.action.rawValue,
          target: project, result: result.status.rawValue,
          succeeded: [.succeeded, .succeededWithWarnings].contains(result.status))
        speak(formatted, role: [.succeeded, .succeededWithWarnings].contains(result.status) ? .assistant : .error)
        completeCurrentStep(succeeded: [.succeeded, .succeededWithWarnings].contains(result.status),
          result: formatted)
      } catch {
        if requestedMode == .workspaceWrite { codingTaskProposalLifecycle = .failed }
        busy = false; codingTask = nil
        memoryStore.recordAction(request: request, action: step.action.rawValue,
          target: project, result: error.localizedDescription, succeeded: false)
        failCurrentStep(error.localizedDescription)
      }
    }
  }
}
