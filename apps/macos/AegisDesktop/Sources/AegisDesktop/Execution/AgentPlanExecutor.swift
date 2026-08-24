import Foundation

struct AgentPlanExecutor {
  private(set) var state: ExecutionState

  init(plan: AgentPlan, request: String, isLearnedSkill: Bool = false) throws {
    let errors = AgentPlanValidator.errors(in: plan, for: request,
      enforceRequestIntent: !isLearnedSkill)
    guard errors.isEmpty else { throw AgentPlannerError.invalidPlan(errors) }
    state = ExecutionState(plan: plan, request: request)
  }

  mutating func next() -> ExecutionDecision {
    if !state.preflightHandled, isUIWorkflow {
      let protected = state.plan.steps.filter {
        $0.action.isUIAction && ApprovalPolicy.requiresApproval(for: $0)
      }
      state.preflightHandled = true
      if !protected.isEmpty {
        let id = UUID(); state.preflightApprovalID = id
        return .preflightApproval(id: id, steps: protected)
      }
    }
    guard state.index < state.plan.steps.count else {
      let summary = PlanExecutionSummary(state: state)
      state.executionState = summary.executionState
      return .finished(summary: summary)
    }
    let step = state.plan.steps[state.index]
    let position = state.index + 1
    if shouldSkip(step) {
      state.outcomes[step.id] = .skipped
      state.index += 1
      return .skipped(step: step, index: position, total: state.plan.steps.count)
    }
    if ApprovalPolicy.requiresApproval(for: step),
      state.approvedStepID != step.id, !state.preflightApprovedSteps.contains(step.id) {
      state.outcomes[step.id] = .awaitingApproval
      state.executionState = .pausedForApproval
      return .approval(step: step, index: position, total: state.plan.steps.count)
    }
    state.outcomes[step.id] = .running
    state.executionState = .running
    return .execute(step: step, index: position, total: state.plan.steps.count)
  }

  mutating func approvePreflight(_ id: UUID) -> Bool {
    guard state.preflightApprovalID == id else { return false }
    state.preflightApprovedSteps = Set(state.plan.steps.filter {
      $0.action.isUIAction && ApprovalPolicy.requiresApproval(for: $0)
    }.map(\.id))
    state.preflightApprovalID = nil
    return true
  }

  mutating func rejectPreflight(_ id: UUID) -> Bool {
    guard state.preflightApprovalID == id else { return false }
    for step in state.plan.steps {
      state.outcomes[step.id] = ApprovalPolicy.requiresApproval(for: step) ? .rejected : .skipped
    }
    state.index = state.plan.steps.count
    state.preflightApprovalID = nil
    return true
  }

  mutating func approve(_ id: UUID) -> Bool {
    guard currentStep?.id == id, currentStep?.action.requiresApproval == true else { return false }
    state.approvedStepID = id
    state.outcomes[id] = .pending
    state.executionState = .running
    return true
  }

  mutating func reject(_ id: UUID) -> Bool {
    guard currentStep?.id == id else { return false }
    state.outcomes[id] = .rejected
    state.index += 1
    state.approvedStepID = nil
    return true
  }

  mutating func complete(_ id: UUID, succeeded: Bool, result: String? = nil) -> Bool {
    guard currentStep?.id == id else { return false }
    state.outcomes[id] = succeeded ? .succeeded : .failed
    if let result { state.results[id] = result }
    state.index += 1
    state.approvedStepID = nil
    return true
  }

  mutating func setResolvedWindowTarget(_ target: ResolvedWindowTarget) {
    state.resolvedWindowTarget = target
  }

  mutating func setResolvedUIElement(_ descriptor: UIElementDescriptor?) {
    state.resolvedUIElement = descriptor
  }

  mutating func setPreflightTarget(_ target: ApprovedUITarget,
                                   resolvedWindow: ResolvedWindowTarget) {
    state.approvedUITarget = target
    state.resolvedWindowTarget = resolvedWindow
  }

  private var currentStep: AgentStep? {
    state.index < state.plan.steps.count ? state.plan.steps[state.index] : nil
  }

  private var isUIWorkflow: Bool { state.plan.steps.contains { $0.action.isUIAction } }

  private func shouldSkip(_ step: AgentStep) -> Bool {
    guard step.dependency == .requiresPreviousSuccess, state.index > 0 else { return false }
    let previous = state.plan.steps[state.index - 1]
    return state.outcomes[previous.id] != .succeeded
  }
}
