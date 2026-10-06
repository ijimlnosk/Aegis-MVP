import Foundation

extension AegisAgent {
  func execute(_ plan: AgentPlan, request: String, skill: LearnedSkill? = nil) {
    do {
      requestTiming?.setPlan(plan.steps.map { $0.action.rawValue })
      if let turn = activeConversationTurnID {
        conversationEvents.setPlan(plan.steps.map { $0.action.rawValue }, turnId: turn)
      }
      planExecutor = try AgentPlanExecutor(plan: plan, request: request, isLearnedSkill: skill != nil)
      activeSkill = skill
      busy = true
      advancePlan()
    } catch {
      busy = false
      speak(error.localizedDescription, role: .error)
    }
  }

  func advancePlan() {
    guard var executor = planExecutor else { return }
    let decision = executor.next()
    planExecutor = executor
    switch decision {
    case .execute(let step, let index, let total):
      executingStepID = step.id
      if let locked = ScreenLockState.blockingMessage(for: step.action) { failCurrentStep(locked); return }
      chat.append(.system, "\(index)/\(total) \(step.action.displayName) 중…")
      execute(step, request: executor.state.request)
    case .approval(let step, let index, let total):
      executingStepID = step.id
      // Checked before asking so the phone never approves a step that cannot run.
      if let locked = ScreenLockState.blockingMessage(for: step.action) { failCurrentStep(locked); return }
      if step.action == .executeCodingTask { codingTaskProposalLifecycle = .awaitingApproval }
      if step.action == .createCommit { gitWorkflowContext.state = .awaitingCommitApproval }
      if step.action == .pushCurrentBranch { gitWorkflowContext.state = .awaitingPushApproval }
      if step.action.isDockerMutation {
        validateThenRequestDockerApproval(step, request: executor.state.request,
          progress: "\(index)/\(total)")
      } else {
        requestStepApproval(step, request: executor.state.request, progress: "\(index)/\(total)")
      }
    case .skipped(let step, let index, let total):
      chat.append(.system, "\(index)/\(total) \(step.action.displayName) 건너뜀 · 이전 단계가 실패했습니다")
      advancePlan()
    case .preflightApproval(let id, let steps):
      if let locked = steps.lazy.compactMap({ ScreenLockState.blockingMessage(for: $0.action) }).first {
        speak(locked, role: .error)
        if planExecutor?.rejectPreflight(id) == true { advancePlan() }
        return
      }
      prepareUIWorkflowPreflight(id: id, steps: steps, request: executor.state.request)
    case .finished(let summary):
      if let answer = PlanExecutionFormatter.format(summary,
        plan: executor.state.plan, request: executor.state.request), !answer.isEmpty {
        speak(answer, role: summary.status == .succeeded ? .assistant : .error)
      }
      finishSkillExecution(executor)
      notifyRemoteFinish(summary, plan: executor.state.plan)
      if let turn = activeConversationTurnID {
        let status: String = switch summary.status {
        case .succeeded: "succeeded"
        case .partiallySucceeded: "partiallySucceeded"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
        conversationEvents.setStatus(status, turnId: turn)
      }
      planExecutor = nil; executingStepID = nil; busy = false
    }
  }

  private func notifyRemoteFinish(_ summary: PlanExecutionSummary, plan: AgentPlan) {
    guard remoteCommandID != nil, let minimum = pushNotifier.configuration?.minimumSeconds,
      PushMessages.shouldNotifyFinish(startedAt: remoteCommandStartedAt, minimumSeconds: minimum) else { return }
    pushNotifier.send(PushMessages.finished(succeeded: summary.status == .succeeded,
      actions: plan.steps.map(\.action), project: plan.steps.compactMap(\.project).first))
  }
}
