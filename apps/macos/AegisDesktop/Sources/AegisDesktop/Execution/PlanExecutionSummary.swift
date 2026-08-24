import Foundation

enum PlanExecutionStatus: Equatable {
  case succeeded, partiallySucceeded, failed, cancelled
}

struct PlanExecutionSummary {
  let status: PlanExecutionStatus
  let succeededSteps: [AgentStep]
  let failedSteps: [AgentStep]
  let skippedSteps: [AgentStep]
  let verifiedOutcome: Bool
  let results: [UUID: String]
  var executionState: PlanExecutionState {
    switch status {
    case .succeeded: .succeeded
    case .partiallySucceeded: .partiallySucceeded
    case .failed: .failed
    case .cancelled: .cancelled
    }
  }

  init(state: ExecutionState) {
    succeededSteps = state.plan.steps.filter { state.outcomes[$0.id] == .succeeded }
    failedSteps = state.plan.steps.filter {
      state.outcomes[$0.id] == .failed || state.outcomes[$0.id] == .rejected
    }
    skippedSteps = state.plan.steps.filter { state.outcomes[$0.id] == .skipped }
    results = state.results
    verifiedOutcome = !state.plan.steps.isEmpty
      && succeededSteps.count == state.plan.steps.count
    if state.plan.steps.isEmpty || verifiedOutcome { status = .succeeded }
    else if !failedSteps.isEmpty,
      failedSteps.allSatisfy({ state.outcomes[$0.id] == .rejected }) {
      status = .cancelled
    } else if succeededSteps.isEmpty { status = .failed }
    else { status = .partiallySucceeded }
  }
}
