import Foundation

enum CapabilityIntentResolver {
  static func plan(for request: String) -> AgentPlan? {
    let normalized = request.lowercased().filter { $0.isLetter || $0.isNumber }
    let capabilityQuestion = [
      "뭘할수있", "뭐할수있", "무엇을할수있", "할수있는기능", "어떤기능",
      "할수있는게뭐", "할수있는건뭐", "할수있는것이뭐", "기능이뭐", "기능뭐",
      "도움말", "사용법", "whatcanyoudo", "capabilities",
    ].contains { normalized.contains($0) }
    guard capabilityQuestion else { return nil }
    return AgentPlan(steps: [], finalAnswer: answer)
  }

  private static var answer: String { AegisGuide.text() }
}
