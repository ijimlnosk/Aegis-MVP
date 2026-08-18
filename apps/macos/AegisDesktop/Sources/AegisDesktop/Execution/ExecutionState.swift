import Foundation

enum StepOutcome: Equatable {
  case succeeded
  case failed
  case rejected
  case skipped
}

struct ExecutionState {
  let plan: AgentPlan
  let request: String
  var index = 0
  var outcomes: [UUID: StepOutcome] = [:]
  var approvedStepID: UUID?
}

enum ExecutionDecision {
  case execute(step: AgentStep, index: Int, total: Int)
  case approval(step: AgentStep, index: Int, total: Int)
  case skipped(step: AgentStep, index: Int, total: Int)
  case finished(finalAnswer: String?)
}
