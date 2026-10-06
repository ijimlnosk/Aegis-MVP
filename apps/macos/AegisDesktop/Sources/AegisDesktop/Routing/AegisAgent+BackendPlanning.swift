import Foundation

extension AegisAgent {
  func planWithBackend(_ message: String) {
    busy = true
    recordActivity("AI 백엔드 행동 계획 생성")
    Task {
      do {
        if let candidate = SemanticRouter.candidate(for: message,
          repository: memoryStore.repository, gitContext: gitWorkflowContext) {
          await routeSemantic(message, candidate: candidate); return
        }
        if let developerPlan = DeveloperIntentResolver.plan(for: message,
          repository: memoryStore.repository) {
          busy = false; execute(developerPlan, request: message); return
        }
        if let projectPlan = ProjectIntentResolver.plan(for: message,
          repository: memoryStore.repository) {
          busy = false; execute(projectPlan, request: message); return
        }
        let memory = MemoryRetriever.relevant(to: message, repository: memoryStore.repository)
        let plan = try await AgentPlanner.plan(for: message, memory: memory,
          metrics: requestTiming?.planner)
        busy = false
        execute(plan, request: message)
      } catch {
        busy = false
        speak(error.localizedDescription, role: .error)
      }
    }
  }

  private func routeSemantic(_ message: String, candidate: SemanticRouteCandidate) async {
    let decision: SemanticRouteDecision
    do {
      decision = try await SemanticRouter.classify(message, candidate: candidate,
        gitContext: gitWorkflowContext)
    } catch {
      busy = false
      speak(SemanticRouter.failureMessage(for: candidate), role: .error)
      return
    }
    busy = false
    switch decision {
    case .developer(let project, let developer):
      switch DeveloperSemanticResolver.resolve(developer, request: message, project: project,
        repository: memoryStore.repository) {
      case .plan(let plan): execute(plan, request: message)
      case .message(let value): speak(value)
      }
    case .gitWorkflow(let git):
      if let continuation = GitWorkflowSemanticResolver.resolve(git, request: message,
        repository: memoryStore.repository, context: &gitWorkflowContext) {
        switch continuation {
        case .plan(let plan): execute(plan, request: message)
        case .message(let value): speak(value)
        }
      } else {
        speak("커밋 후속 요청을 이해하지 못했습니다. 요청을 더 구체적으로 말씀해 주세요.")
      }
    }
  }
}
