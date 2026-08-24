import Foundation

enum AIBackendIntentResolver {
  static func plan(for request: String) -> AgentPlan? {
    let text = request.lowercased()
    guard ["ai 백엔드 상태", "ai backend status", "ollama 상태", "모델 서버 상태"]
      .contains(where: text.contains) else { return nil }
    return AgentPlan(step: AgentStep(action: .getAIBackendStatus))
  }
}

enum AIBackendDiagnostics {
  static func format(planner: OllamaBackendStatus, vision: VisionBackendStatus?,
                     concurrency: (active: Bool, queued: Int)) -> String {
    let plannerHost = planner.endpoint?.host ?? "invalid"
    let visionHost = vision?.endpoint?.host ?? "invalid"
    return """
    AI 백엔드 상태
    Planner:
    - backend: \(planner.backend.rawValue)
    - host: \(plannerHost)
    - model: \(planner.model)
    - status: \(planner.availability.rawValue)
    Vision:
    - backend: \(vision?.configured.rawValue ?? "unavailable")
    - host: \(visionHost)
    - model: \(vision?.model ?? "unknown")
    - status: \(vision?.availability.rawValue ?? "invalidConfiguration")
    Shared inference: \(concurrency.active ? "active" : "idle") · queued \(concurrency.queued)
    """
  }
}

extension AegisAgent {
  func runAIBackendDiagnostics(request: String) {
    busy = true
    Task {
      let planner = await OllamaTransport().status()
      let vision = await screenInspector.visionBackendStatus(refresh: true)
      let concurrency = await OllamaInferenceCoordinator.shared.status()
      busy = false
      finishReadTool(AIBackendDiagnostics.format(planner: planner, vision: vision,
        concurrency: concurrency), action: AgentAction.getAIBackendStatus.rawValue,
        request: request, target: "ollama")
    }
  }
}
