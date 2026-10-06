import Foundation

extension AegisAgent {
  func routeValidationFollowUp(_ kind: SemanticRouteKind?, message: String) -> Bool {
    switch kind {
    case .detailedLint, .fixValidation: runValidationRepair(kind, message: message)
    case .explainValidation: explainValidation()
    default: return false
    }
    return true
  }

  func routeCodingContinuation(_ kind: SemanticRouteKind?, message: String) -> Bool {
    let explicitProject = ProjectEntityResolver.resolve(in: message, repository: memoryStore.repository)
    if let project = explicitProject, !codingFindings.isEmpty,
      !codingFindings.contains(where: { $0.projectId == project.name.lowercased() }) {
      codingFindings.removeAll(); activeCodingContinuation = nil
    }
    guard kind == .codingContinuation, let continuation = CodingContinuationIntentResolver.resolve(message,
      findings: codingFindings, explicitProject: explicitProject) else { return false }
    switch continuation {
    case .write(let intent):
      activeCodingContinuation = intent.finding
      execute(intent.plan, request: message)
    case .explain(let finding):
      speak(CodingFindingFormatter.explain(finding))
    case .inspectMore(let finding):
      activeCodingContinuation = finding
      execute(readOnlyAnalysisPlan(message, project: finding.projectName), request: message)
    case .findAnother(let finding):
      activeCodingContinuation = nil
      execute(readOnlyAnalysisPlan(message, project: finding.projectName), request: message)
    case .clarify:
      speak("최근 개선점이 여러 프로젝트에 있습니다. 어느 프로젝트의 문제인지 말해 주세요.")
    case .forget:
      codingFindings.removeAll(); activeCodingContinuation = nil
      speak("이전 코딩 개선점을 이어서 사용하지 않겠습니다.")
    }
    return true
  }

  private func runValidationRepair(_ kind: SemanticRouteKind?, message: String) {
    busy = true
    Task {
      let project = await validationFollowUpProject(message)
      busy = false
      guard let project else {
        speak(kind == .detailedLint ? "어느 프로젝트의 lint 경고를 조사할지 프로젝트명을 말씀해 주세요."
          : "어느 프로젝트의 검증 문제를 수정할지 프로젝트명을 말씀해 주세요.")
        return
      }
      let plan = kind == .detailedLint
        ? CodingResultFollowUpResolver.detailedLintPlan(request: message, project: project.name)
        : CodingResultFollowUpResolver.fixPlan(request: message, project: project.name)
      execute(plan, request: message)
    }
  }

  /// Prefers the project named in the request, then the last coding result, then the saved response.
  private func validationFollowUpProject(_ message: String) async -> ProjectEntity? {
    let latest = await codingCoordinator.lastResult
    let saved = conversationEvents.latestValidationResponse(
      sessionId: conversationSessionID, excluding: activeConversationTurnID)
    return ProjectEntityResolver.resolve(in: message, repository: memoryStore.repository)
      ?? latest.flatMap { ProjectEntityResolver.resolve(name: $0.project, repository: memoryStore.repository) }
      ?? saved.flatMap { ProjectEntityResolver.resolve(in: $0, repository: memoryStore.repository) }
  }

  private func explainValidation() {
    busy = true
    Task {
      let result = await codingCoordinator.lastResult
      busy = false
      if let result {
        speak(CodingTaskFormatter.validationExplanation(result))
      } else if let saved = conversationEvents.latestValidationResponse(
        sessionId: conversationSessionID, excluding: activeConversationTurnID) {
        // Re-running scripts here would bypass approval, so only allowlisted projects refresh.
        if let project = ProjectEntityResolver.resolve(in: saved, repository: memoryStore.repository),
          AutoValidationProjects.allows(project.name, in: AutoValidationProjects.current),
          let root = try? ProjectCommandPolicy.projectURL(project.name, repository: memoryStore.repository) {
          let report = ProjectValidationService.run(project: project.name, root: root,
            repository: memoryStore.repository)
          speak(CodingTaskFormatter.validationExplanation(project: project.name, checks: report.checks))
        } else {
          speak("최근 저장 기록 기준입니다.\n\n\(saved)")
        }
      } else {
        speak("최근 코드 수정 검증 결과가 없습니다.")
      }
    }
  }

  private func readOnlyAnalysisPlan(_ message: String, project: String) -> AgentPlan {
    AgentPlan(step: AgentStep(action: .analyzeProjectWithCodingAgent,
      content: message, project: project, codingMode: .readOnlyAnalysis))
  }
}
