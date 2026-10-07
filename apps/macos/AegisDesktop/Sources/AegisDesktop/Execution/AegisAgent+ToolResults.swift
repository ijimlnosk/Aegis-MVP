import Foundation

extension AegisAgent {
  func finishReadTool(_ result: String, action: String, request: String, target: String = "",
                      succeeded explicitSuccess: Bool? = nil) {
    // Reaching this point means the underlying call returned without throwing --
    // any real failure already went through the separate catch -> failCurrentStep
    // path. The result text is informational (git status, server state, UI
    // status, ...) and must never retroactively flip a successful read to
    // "failed" just because it mentions a word like "필요합니다" or "오류".
    let succeeded = explicitSuccess ?? true
    LearningMemory.record(request: request, action: action, result: result)
    memoryStore.recordAction(request: request, action: action, target: target,
      result: result, succeeded: succeeded)
    speak(result)
    completeCurrentStep(succeeded: succeeded, result: result)
  }

  func runServerTool(_ tool: ServerTool, request: String, arguments: [String: Any] = [:], approved: Bool = false) {
    guard tool.requiresApproval == approved else {
      speak("승인 상태가 올바르지 않아 서버 작업을 실행하지 않았습니다.")
      return
    }
    busy = true
    recordActivity("sol-server · \(tool.rawValue)")
    Task {
      do {
        let result = try await ServerAgentClient.call(tool, arguments: arguments)
        busy = false
        let target = arguments["container"] as? String ?? arguments["project"] as? String ?? "sol-server"
        finishReadTool(ServerResultFormatter.display(tool, raw: result), action: tool.rawValue,
          request: request, target: target)
      } catch {
        let target = arguments["container"] as? String ?? arguments["project"] as? String ?? "sol-server"
        memoryStore.recordAction(request: request, action: tool.rawValue, target: target,
          result: error.localizedDescription, succeeded: false)
        speak(error.localizedDescription, role: .error)
        completeCurrentStep(succeeded: false)
      }
    }
  }

  func runRememberedProjectStatus(_ project: String, request: String) {
    busy = true
    Task {
      do {
        let result = try MemoryProjectTool.status(project: project, repository: memoryStore.repository)
        busy = false
        finishReadTool(result, action: AgentAction.getRememberedProjectStatus.rawValue,
          request: request, target: project)
      } catch {
        memoryStore.recordAction(request: request, action: AgentAction.getRememberedProjectStatus.rawValue,
          target: project, result: error.localizedDescription, succeeded: false)
        speak(error.localizedDescription, role: .error)
        completeCurrentStep(succeeded: false)
      }
    }
  }
}
