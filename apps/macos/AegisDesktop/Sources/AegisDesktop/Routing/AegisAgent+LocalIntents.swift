import Foundation

extension AegisAgent {
  /// Deterministic resolvers, tried in priority order before any AI backend call.
  func routeLocalIntent(_ message: String) -> Bool {
    let repository = memoryStore.repository
    if let readOnlyCoding = CodingIntentResolver.explicitReadOnlyPlan(for: message,
      repository: repository, recentWindow: recentUIWindowTarget) {
      execute(readOnlyCoding, request: message); return true
    }
    if let autonomous = AutonomousDevelopmentIntentResolver.plan(for: message,
      repository: repository, active: activeDevelopmentCandidate, recentWindow: recentUIWindowTarget) {
      execute(autonomous, request: message); return true
    }
    if let skillIntent = SkillIntentParser.parse(message) {
      do { speak(try skillStore.handle(skillIntent)) }
      catch { speak(error.localizedDescription, role: .error) }
      return true
    }
    if let memoryIntent = MemoryIntentParser.parse(message) {
      let result = memoryStore.handle(memoryIntent)
      speak(result, role: result.hasPrefix("메모리 저장소 오류") ? .error : .assistant)
      return true
    }
    let plan = ValidationRunIntentResolver.plan(for: message, repository: repository)
      ?? UIIntentResolver.plan(for: message, repository: repository)
      ?? ScreenIntentResolver.plan(for: message, repository: repository)
      ?? CodingIntentResolver.plan(for: message, repository: repository, recentWindow: recentUIWindowTarget)
      ?? GitWorkflowIntentResolver.plan(for: message, repository: repository, context: gitWorkflowContext)
    if let plan { execute(plan, request: message); return true }
    if let skill = matchedSkill(message) {
      execute(AgentPlan(steps: skill.steps), request: message, skill: skill); return true
    }
    return false
  }
}
