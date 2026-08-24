import Foundation

enum RemoteControlIntentResolver {
  static func plan(for request: String) -> AgentPlan? {
    let normalized = request.lowercased().filter { $0.isLetter || $0.isNumber }
    guard ["원격제어상태", "remotestatus", "remotegatewaystatus"].contains(where: normalized.contains) else {
      return nil
    }
    return AgentPlan(step: AgentStep(action: .getRemoteControlStatus))
  }
}
