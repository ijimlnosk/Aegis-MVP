import Foundation

extension AegisAgent {
  func requestApproval(id: UUID = UUID(), kind: String, title: String, detail: String,
                               request: String, arguments: [String: String]) {
    let action = PendingMacAction(id: id, kind: kind, title: title, detail: detail,
      request: request, arguments: arguments)
    pendingMacAction = action
    chat.appendApproval(id: action.id, content: "\(title)\n\(detail)")
    LearningMemory.record(request: request, action: kind, result: "승인 대기")
    startWakeListening()
  }

  func interpretMacApproval(_ text: String) {
    let compact = text.replacingOccurrences(of: " ", with: "")
    if ["취소", "그만", "하지마"].contains(where: compact.contains) { cancelMacAction(); return }
    if ["실행", "진행", "승인", "응", "좋아", "그래"].contains(where: compact.contains) { confirmMacAction(); return }
    reply = "실행할지 취소할지 다시 말씀해 주세요."
    startWakeListening()
  }

  func confirmMacAction() {
    guard let action = pendingMacAction else { return }
    if action.kind == AgentAction.createCommit.rawValue,
      action.arguments["gitCommitPlanId"] != gitWorkflowContext.activeCommitPlanId?.uuidString {
      pendingMacAction = nil; failCurrentStep(GitWorkflowError.noActiveCommitPlan.localizedDescription); return
    }
    chat.resolveApproval(id: action.id, state: .approved)
    chat.append(.system, "작업을 승인했습니다. 실행 결과를 기다리는 중입니다.")
    pendingMacAction = nil
    if action.kind == "ui_workflow_preflight" {
      guard planExecutor?.approvePreflight(action.id) == true else {
        failCurrentStep("승인할 UI 실행 계획을 찾지 못했습니다."); return
      }
      advancePlan(); return
    }
    guard planExecutor?.approve(action.id) == true else {
      failCurrentStep("승인할 실행 단계를 찾지 못했습니다.")
      return
    }
    if action.kind == AgentAction.executeCodingTask.rawValue {
      codingTaskProposalLifecycle = .approved
    }
    if action.kind == AgentAction.createCommit.rawValue { gitWorkflowContext.state = .committing }
    if action.kind == AgentAction.pushCurrentBranch.rawValue { gitWorkflowContext.state = .pushing }
    advancePlan()
  }

  func cancelMacAction() {
    guard let action = pendingMacAction else { return }
    let kind = action.kind
    chat.resolveApproval(id: action.id, state: .rejected)
    pendingMacAction = nil
    LearningMemory.record(request: "사용자 취소", action: kind, result: "취소")
    chat.append(.system, "작업을 거절했습니다. Server Agent나 Mac 도구를 호출하지 않았습니다.")
    if kind == "ui_workflow_preflight" {
      if planExecutor?.rejectPreflight(action.id) == true { advancePlan() }
    } else if planExecutor?.reject(action.id) == true {
      if kind == AgentAction.executeCodingTask.rawValue {
        codingTaskProposalLifecycle = .rejected
        activeCodingTaskProposal = nil; activeCodingContinuation = nil
      }
      if kind == AgentAction.executeDevelopmentTask.rawValue {
        Task { await autonomousDevelopment.reject() }
      }
      if kind == AgentAction.createCommit.rawValue { gitWorkflowContext.state = .cancelled }
      if kind == AgentAction.pushCurrentBranch.rawValue { gitWorkflowContext.state = .committed }
      advancePlan()
    }
  }

  func approveChatAction(_ id: UUID) {
    if pendingSkillProposal?.candidate.id == id { saveSkillProposal(); return }
    if pendingMacAction?.id == id { confirmMacAction(); return }
    if pendingKakaoApprovalID == id { confirmKakaoMessage() }
  }

  func rejectChatAction(_ id: UUID) {
    if pendingSkillProposal?.candidate.id == id { rejectSkillProposal(); return }
    if pendingMacAction?.id == id { cancelMacAction(); return }
    if pendingKakaoApprovalID == id { cancelKakaoMessage() }
  }

  func serverActionLabel(_ operation: String) -> String {
    ["start": "시작", "stop": "중지", "restart": "재시작"][operation] ?? "변경"
  }
}
