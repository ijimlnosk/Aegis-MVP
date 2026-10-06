import Foundation

extension AegisAgent {
  func execute(_ step: AgentStep, request: String) {
    let action = step.action.rawValue
    recordActivity("AI 선택: \(action)")
    switch step.action {
    case .kakaoMessage:
      guard let recipient = step.recipient?.trimmingCharacters(in: .whitespacesAndNewlines), !recipient.isEmpty,
            let body = step.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
        failCurrentStep("받는 사람이나 보낼 내용을 이해하지 못했습니다.")
        return
      }
      sendKakao(KakaoMessage(recipient: recipient, body: body), request: request)
    case .openApplication:
      let application = step.application?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !application.isEmpty else { failCurrentStep("열 앱을 이해하지 못했습니다."); return }
      if let project = step.project { openRememberedProject(project, request: request) }
      else { launch(application, request: request) }
    case .openProject:
      let project = step.project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let application = step.application?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !project.isEmpty, !application.isEmpty else {
        failCurrentStep("프로젝트와 코드 에디터가 필요합니다."); return
      }
      openProject(project, application: application, request: request)
    case .closeApplication:
      let application = step.application?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !application.isEmpty else { failCurrentStep("닫을 앱을 이해하지 못했습니다."); return }
      close(application, request: request)
    case .browserSearch:
      let browser = step.browser?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let site = step.site?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let query = step.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !site.isEmpty else {
        failCurrentStep("브라우저 검색 내용을 이해하지 못했습니다.")
        return
      }
      let selectedBrowser = browser.isEmpty ? "Safari" : browser
      search(browser: selectedBrowser, site: site, query: query, request: request)
    case .getActiveApplication:
      let result = MacTools.activeApplication()
      finishReadTool(result, action: action, request: request)
    case .getSystemStatus:
      finishReadTool(MacToolbox.systemStatus(), action: action, request: request)
    case .getAIBackendStatus:
      runAIBackendDiagnostics(request: request)
    case .getRemoteControlStatus:
      Task {
        let result = await RemoteControlDiagnostics.report(bridge: .load(),
          desktopBridgeStatus: desktopBridgeStatus?() ?? desktopBridge.status)
        finishReadTool(result, action: action, request: request)
      }
    case .listRunningApplications:
      finishReadTool(MacToolbox.runningApplications(), action: action, request: request)
    case .getClipboard:
      finishReadTool(MacToolbox.clipboardText(), action: action, request: request)
    case .getServerStatus:
      runServerTool(.status, request: request)
    case .getDockerContainers:
      runServerTool(.containers, request: request)
    case .getDockerLogs:
      let container = step.container?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !container.isEmpty else { failCurrentStep("확인할 컨테이너 이름이 필요합니다."); return }
      runServerTool(.logs, request: request, arguments: ["container": container, "lines": step.lines ?? 100])
    case .getServerProjectStatus:
      let project = step.project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !project.isEmpty else { failCurrentStep("확인할 서버 프로젝트가 필요합니다."); return }
      runServerTool(.projectStatus, request: request, arguments: ["project": project])
    case .getRememberedProjectStatus:
      let project = step.project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !project.isEmpty else { failCurrentStep("확인할 프로젝트가 필요합니다."); return }
      runRememberedProjectStatus(project, request: request)
    case .getProjectGitStatus, .getProjectBranch, .getProjectDiffSummary,
         .getProjectRecentCommits, .getProjectChangedFiles, .getProjectPackageScripts,
         .getProjectHealth, .assessProjectDeploymentReadiness, .runProjectTypecheck, .runProjectTests, .runProjectLint,
         .runProjectBuild, .startDevelopmentSession, .endDevelopmentSession,
         .getDevelopmentRecap, .getTodayDevelopmentSummary:
      runDeveloperTool(step, request: request)
    case .getCodingAgentStatus, .getCodingAgentRecentDiagnostics,
      .analyzeProjectWithCodingAgent, .proposeCodingTask,
         .executeCodingTask, .reviewCodingTaskResult, .verifyCodingTask, .rollbackCodingTask:
      runCodingTool(step, request: request)
    case .discoverDevelopmentTask, .rankDevelopmentCandidates, .proposeDevelopmentTask,
         .executeDevelopmentTask, .verifyDevelopmentTask, .repairDevelopmentTask,
         .getAutonomousDevelopmentStatus:
      runAutonomousDevelopmentTool(step, request: request)
    case .inspectGitDiff, .proposeCommitPlan, .createCommit, .getRemoteStatus,
         .proposePush, .pushCurrentBranch, .getCIStatus, .getPullRequestStatus,
         .getGitWorkflowStatus:
      runGitWorkflowTool(step, request: request)
    case .captureScreen, .inspectScreen, .inspectActiveWindow,
         .inspectScreenWithProjectContext, .getScreenAwarenessStatus,
         .listVisibleWindows, .inspectWindow:
      runScreenTool(step, request: request)
    case .getUIControlStatus, .getVSCodeQuickOpenStatus, .activateApplication, .focusWindow, .closeWindow,
         .listUIElements, .inspectUIElement, .pressUIElement, .focusUIElement,
         .setUIText, .appendUIText, .pressKeyboardShortcut, .scrollUI, .selectMenuItem:
      runUITool(step, request: request)
    case .startDockerContainer, .stopDockerContainer, .restartDockerContainer:
      let container = step.container?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !container.isEmpty else { failCurrentStep("변경할 컨테이너 이름이 필요합니다."); return }
      runValidatedDockerMutation(step, container: container, request: request)
    case .setClipboard:
      let content = step.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !content.isEmpty else { failCurrentStep("클립보드에 저장할 내용을 이해하지 못했습니다."); return }
      finishReadTool(MacToolbox.setClipboard(content), action: action, request: request, target: "clipboard")
    case .findProjectPath:
      let name = step.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !name.isEmpty else { failCurrentStep("찾을 프로젝트 이름을 이해하지 못했습니다."); return }
      if let path = ProjectDiscovery.find(named: name) {
        pendingProjectDiscovery = (name: name, path: path)
        finishReadTool("\"\(name)\" 위치를 찾았습니다: \(path)\n등록하려면 \"등록해\"라고 말씀해 주세요.",
          action: action, request: request, target: name)
      } else {
        finishReadTool("\"\(name)\"를 찾지 못했습니다. 홈 디렉터리 바로 아래나 ~/Developer, ~/Projects, ~/Documents 안에 있는지 확인해 주세요.",
          action: action, request: request, target: name)
      }
    default:
      failCurrentStep("지원하지 않는 실행 단계입니다.")
    }
  }
}
