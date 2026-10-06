import Foundation

extension AegisAgent {
  func requestStepApproval(_ step: AgentStep, request: String, progress: String) {
    let title: String
    let detail: String
    var arguments: [String: String] = [:]
    switch step.action {
    case .kakaoMessage:
      title = "\(step.recipient ?? "")에게 카카오톡 전송"
      detail = step.body ?? ""
    case .openApplication:
      title = step.project.map { "\($0) 프로젝트 열기" } ?? "\(step.application ?? "") 실행"
      detail = "앱 또는 프로젝트를 열고 화면 앞으로 가져옵니다."
    case .openProject:
      title = "\(step.project ?? "") 프로젝트 열기"
      detail = "허용된 \(step.application ?? "코드 에디터")에서 등록된 프로젝트를 엽니다."
    case .closeApplication:
      title = "\(step.application ?? "") 종료"; detail = "저장하지 않은 작업이 영향을 받을 수 있습니다."
    case .browserSearch:
      title = "브라우저 검색"; detail = "\(step.browser ?? "Safari")에서 \(step.site ?? "") · \(step.query ?? "")"
    case .setClipboard:
      title = "클립보드 변경"; detail = String((step.content ?? "").prefix(300))
    case .setUIText, .appendUIText:
      title = "UI 텍스트 입력"
      detail = "\(step.uiLabel ?? "입력 필드")에 '\(String((step.content ?? "").prefix(300)))'을 입력합니다."
    case .pressUIElement, .selectMenuItem:
      title = "UI 요소 실행"; detail = "\(step.uiLabel ?? "지정한 요소")을 실행합니다."
    case .closeWindow:
      title = "창 닫기"
      detail = "\(step.project ?? step.application ?? "현재") 창만 닫습니다. 앱은 종료하지 않습니다."
    case .runProjectTypecheck, .runProjectTests, .runProjectLint, .runProjectBuild:
      title = "\(step.project ?? "") 프로젝트 검증"
      detail = "등록된 package.json의 \(step.action.rawValue.replacingOccurrences(of: "run_project_", with: "")) 스크립트를 실행합니다."
    case .verifyCodingTask:
      title = "\(step.project ?? "") 코딩 작업 검증"
      detail = "등록된 package.json의 typecheck/lint/test/build 스크립트를 실행합니다."
    case .executeCodingTask:
      title = "\(step.project ?? "") 코딩 작업"
      detail = activeCodingTaskProposal.map(CodingFindingProposalFormatter.format)
        ?? CodingFindingProposalFormatter.format(project: step.project ?? "",
          request: step.content ?? request, finding: activeCodingContinuation)
    case .executeDevelopmentTask, .repairDevelopmentTask:
      title = "\(step.project ?? "") 자율 개발 작업"
      detail = activeDevelopmentCandidate.map {
        AutonomousDevelopmentFormatter.proposal($0, executable: true)
      } ?? "승인된 작은 개발 작업을 Codex로 수행하고 Git 변경 및 검증 결과를 확인합니다."
    case .rollbackCodingTask:
      title = "\(step.project ?? "") 코딩 작업 롤백"
      detail = "해당 작업에 독립적으로 귀속되고 이후 변경이 없는 tracked 파일만 되돌립니다."
    case .createCommit:
      title = "\(step.project ?? "") 커밋 생성"
      detail = gitWorkflowContext.plan.map(GitWorkflowFormatter.plan)
        ?? "승인된 파일만 정확히 stage하고 로컬 커밋을 생성합니다. push는 수행하지 않습니다."
    case .pushCurrentBranch:
      title = "\(step.project ?? "") 현재 브랜치 push"
      detail = gitWorkflowContext.pushProposal.map(GitWorkflowFormatter.push)
        ?? "현재 브랜치를 일반 push합니다. force push는 지원하지 않습니다."
    case .startDockerContainer, .stopDockerContainer, .restartDockerContainer:
      let operation = step.action.rawValue.replacingOccurrences(of: "_docker_container", with: "")
      title = "\(step.container ?? "") 컨테이너 \(serverActionLabel(operation))"
      detail = "sol-server에서 Docker \(operation) 작업을 실행합니다."
    default:
      failCurrentStep("승인이 필요하지 않은 단계입니다."); return
    }
    arguments["progress"] = progress
    if let project = step.project { arguments["project"] = project }
    if step.action == .createCommit, let id = gitWorkflowContext.activeCommitPlanId {
      arguments["gitCommitPlanId"] = id.uuidString
    }
    requestApproval(id: step.id, kind: step.action.rawValue, title: "\(progress) \(title)",
      detail: detail, request: request, arguments: arguments)
  }

  func prepareUIWorkflowPreflight(id: UUID, steps: [AgentStep], request: String) {
    busy = true
    Task {
      do {
        let windows = try await visibleWindows.list()
        guard let targetStep = planExecutor?.state.plan.steps.first(where: {
          $0.action.isUIAction && $0.action != .getUIControlStatus
        }) else { throw UIInteractionError.targetNotFound("승인할 UI") }
        if targetStep.application == nil, recentUIWindowTarget == nil {
          throw UIInteractionError.targetNotFound("승인할 정확한 창")
        }
        let window = try UIWindowTargetResolver.resolve(step: targetStep, windows: windows,
          workflow: nil, recent: recentUIWindowTarget)
        let approved = try ApprovedUITarget(window: window,
          semanticTarget: steps.map { $0.action.rawValue }.joined(separator: ","))
        let resolved = try ResolvedWindowTarget(window)
        planExecutor?.setPreflightTarget(approved, resolvedWindow: resolved)
        busy = false
        let detail = steps.map { approvalDescription($0) }.joined(separator: "\n")
        requestApproval(id: id, kind: "ui_workflow_preflight", title: "UI 작업 사전 승인",
          detail: detail, request: request, arguments: [:])
      } catch {
        busy = false; speak(error.localizedDescription, role: .error)
        if planExecutor?.rejectPreflight(id) == true { advancePlan() }
      }
    }
  }

  private func approvalDescription(_ step: AgentStep) -> String {
    switch step.action {
    case .closeWindow: "- \(step.project ?? step.application ?? "현재") 창 닫기"
    case .setUIText, .appendUIText:
      "- \(step.uiLabel ?? "UI 필드")에 '\(String((step.content ?? "").prefix(300)))' 입력"
    case .pressUIElement, .selectMenuItem: "- \(step.uiLabel ?? "UI 요소") 실행"
    default: "- \(step.action.rawValue)"
    }
  }

  func completeCurrentStep(succeeded: Bool, result: String? = nil) {
    guard let id = executingStepID, var executor = planExecutor else { return }
    let action = executor.state.plan.steps.first { $0.id == id }?.action.rawValue ?? "unknown"
    let position = executor.state.index + 1
    let total = executor.state.plan.steps.count
    guard executor.complete(id, succeeded: succeeded, result: result) else { return }
    if let turn = activeConversationTurnID {
      conversationEvents.appendAction(.init(action: action, succeeded: succeeded, result: result), turnId: turn)
    }
    planExecutor = executor
    chat.append(.system, "\(position)/\(total) \(succeeded ? "완료" : "실패")")
    advancePlan()
  }

  func failCurrentStep(_ message: String) {
    speak(message, role: .error)
    completeCurrentStep(succeeded: false, result: message)
  }
}
