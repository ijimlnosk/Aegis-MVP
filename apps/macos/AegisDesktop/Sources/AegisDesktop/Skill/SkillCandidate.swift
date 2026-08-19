import Foundation

struct SkillCandidate: Identifiable, Equatable {
  let id: UUID
  let suggestedName: String
  let steps: [AgentStep]
  let evidenceCount: Int

  init(id: UUID = UUID(), suggestedName: String, steps: [AgentStep], evidenceCount: Int) {
    self.id = id; self.suggestedName = suggestedName; self.steps = steps
    self.evidenceCount = evidenceCount
  }
}

struct PendingSkillProposal {
  let candidate: SkillCandidate
}

struct SkillPattern: Hashable {
  let actions: [String]
  init(steps: [AgentStep]) {
    actions = steps.map { step in
      let target = step.project ?? step.container ?? step.application ?? step.recipient
        ?? [step.browser, step.site, step.query].compactMap { $0 }.joined(separator: ":")
      return "\(step.action.rawValue)|\(target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(step.dependency.rawValue)"
    }
  }
}
