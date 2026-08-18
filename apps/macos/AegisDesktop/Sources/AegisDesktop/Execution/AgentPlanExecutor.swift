import Foundation

struct AgentPlanExecutor {
  private(set) var state: ExecutionState

  init(plan: AgentPlan, request: String) throws {
    let errors = AgentPlanValidator.errors(in: plan, for: request)
    guard errors.isEmpty else { throw AgentPlannerError.invalidPlan(errors) }
    state = ExecutionState(plan: plan, request: request)
  }

  mutating func next() -> ExecutionDecision {
    guard state.index < state.plan.steps.count else {
      return .finished(finalAnswer: state.plan.finalAnswer)
    }
    let step = state.plan.steps[state.index]
    let position = state.index + 1
    if shouldSkip(step) {
      state.outcomes[step.id] = .skipped
      state.index += 1
      return .skipped(step: step, index: position, total: state.plan.steps.count)
    }
    if step.action.requiresApproval, state.approvedStepID != step.id {
      return .approval(step: step, index: position, total: state.plan.steps.count)
    }
    return .execute(step: step, index: position, total: state.plan.steps.count)
  }

  mutating func approve(_ id: UUID) -> Bool {
    guard currentStep?.id == id, currentStep?.action.requiresApproval == true else { return false }
    state.approvedStepID = id
    return true
  }

  mutating func reject(_ id: UUID) -> Bool {
    guard currentStep?.id == id else { return false }
    state.outcomes[id] = .rejected
    state.index += 1
    state.approvedStepID = nil
    return true
  }

  mutating func complete(_ id: UUID, succeeded: Bool) -> Bool {
    guard currentStep?.id == id else { return false }
    state.outcomes[id] = succeeded ? .succeeded : .failed
    state.index += 1
    state.approvedStepID = nil
    return true
  }

  private var currentStep: AgentStep? {
    state.index < state.plan.steps.count ? state.plan.steps[state.index] : nil
  }

  private func shouldSkip(_ step: AgentStep) -> Bool {
    guard step.dependency == .requiresPreviousSuccess, state.index > 0 else { return false }
    let previous = state.plan.steps[state.index - 1]
    return state.outcomes[previous.id] != .succeeded
  }
}
