import Foundation

enum StepOutcome: Equatable {
  case pending
  case running
  case succeeded
  case awaitingApproval
  case failed
  case rejected
  case skipped
}

enum PlanExecutionState: Equatable {
  case running, pausedForApproval, succeeded, partiallySucceeded, failed, cancelled
}

struct ExecutionState {
  let plan: AgentPlan
  let request: String
  var index = 0
  var outcomes: [UUID: StepOutcome] = [:]
  var results: [UUID: String] = [:]
  var approvedStepID: UUID?
  var resolvedWindowTarget: ResolvedWindowTarget?
  var resolvedUIElement: UIElementDescriptor?
  var approvedUITarget: ApprovedUITarget?
  var preflightApprovalID: UUID?
  var preflightHandled = false
  var preflightApprovedSteps = Set<UUID>()
  var executionState: PlanExecutionState = .running
}

enum ExecutionDecision {
  case execute(step: AgentStep, index: Int, total: Int)
  case approval(step: AgentStep, index: Int, total: Int)
  case skipped(step: AgentStep, index: Int, total: Int)
  case preflightApproval(id: UUID, steps: [AgentStep])
  case finished(summary: PlanExecutionSummary)
}
