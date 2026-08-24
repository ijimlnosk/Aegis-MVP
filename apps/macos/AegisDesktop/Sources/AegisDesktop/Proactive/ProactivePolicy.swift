enum ProactivePermission: Equatable {
  case autoObserve
  case autoInvestigateReadOnly
  case suggestOnly
  case approvalRequired
  case forbidden
}

enum ProactivePolicy {
  static func permission(for action: AgentAction) -> ProactivePermission {
    switch action {
    case .getServerStatus, .getDockerContainers, .getSystemStatus,
         .getActiveApplication, .listRunningApplications, .getRememberedProjectStatus,
         .getProjectGitStatus, .getProjectBranch, .getProjectChangedFiles, .getProjectHealth:
      .autoObserve
    case .findProjectPath: .suggestOnly
    case .getDockerLogs, .getServerProjectStatus, .getProjectDiffSummary,
         .getProjectRecentCommits, .getProjectPackageScripts, .assessProjectDeploymentReadiness, .getDevelopmentRecap,
         .getTodayDevelopmentSummary: .autoInvestigateReadOnly
    case .startDockerContainer, .stopDockerContainer, .restartDockerContainer,
         .openApplication, .openProject, .closeApplication, .browserSearch, .setClipboard, .kakaoMessage:
      .approvalRequired
    case .getClipboard, .startDevelopmentSession, .endDevelopmentSession,
         .runProjectTypecheck, .runProjectTests, .runProjectLint, .runProjectBuild,
         .captureScreen, .inspectScreen, .inspectActiveWindow,
         .inspectScreenWithProjectContext, .getScreenAwarenessStatus, .getAIBackendStatus,
         .getRemoteControlStatus,
         .listVisibleWindows, .inspectWindow, .getUIControlStatus, .getVSCodeQuickOpenStatus,
         .activateApplication,
         .focusWindow, .closeWindow, .listUIElements, .inspectUIElement, .pressUIElement,
         .focusUIElement, .setUIText, .appendUIText, .pressKeyboardShortcut, .scrollUI,
         .selectMenuItem, .getCodingAgentStatus, .getCodingAgentRecentDiagnostics,
         .analyzeProjectWithCodingAgent,
         .proposeCodingTask, .executeCodingTask, .reviewCodingTaskResult,
         .verifyCodingTask, .rollbackCodingTask, .discoverDevelopmentTask,
         .rankDevelopmentCandidates, .proposeDevelopmentTask, .executeDevelopmentTask,
         .verifyDevelopmentTask, .repairDevelopmentTask,
         .getAutonomousDevelopmentStatus, .inspectGitDiff, .proposeCommitPlan,
         .createCommit, .getRemoteStatus, .proposePush, .pushCurrentBranch,
         .getCIStatus, .getPullRequestStatus, .getGitWorkflowStatus: .suggestOnly
    case .answer, .unknown: .forbidden
    }
  }

  static func mayAutoExecute(_ action: AgentAction) -> Bool {
    [.autoObserve, .autoInvestigateReadOnly].contains(permission(for: action))
  }
}
