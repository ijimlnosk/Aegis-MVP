struct AgentPlan: Codable {
  static let maximumSteps = 5
  let steps: [AgentStep]
  let finalAnswer: String?

  init(steps: [AgentStep], finalAnswer: String? = nil) {
    self.steps = steps
    self.finalAnswer = finalAnswer
  }

  init(step: AgentStep, finalAnswer: String? = nil) {
    self.init(steps: [step], finalAnswer: finalAnswer)
  }
}
