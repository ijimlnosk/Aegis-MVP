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
    case .getDockerLogs, .getServerProjectStatus, .getProjectDiffSummary,
         .getProjectRecentCommits, .getProjectPackageScripts, .assessProjectDeploymentReadiness, .getDevelopmentRecap,
         .getTodayDevelopmentSummary: .autoInvestigateReadOnly
    case .startDockerContainer, .stopDockerContainer, .restartDockerContainer,
         .openApplication, .openProject, .closeApplication, .browserSearch, .setClipboard, .kakaoMessage:
      .approvalRequired
    case .getClipboard, .startDevelopmentSession, .endDevelopmentSession,
         .runProjectTypecheck, .runProjectTests, .runProjectLint, .runProjectBuild,
         .captureScreen, .inspectScreen, .inspectActiveWindow,
         .inspectScreenWithProjectContext, .getScreenAwarenessStatus,
         .listVisibleWindows, .inspectWindow: .suggestOnly
    case .answer, .unknown: .forbidden
    }
  }

  static func mayAutoExecute(_ action: AgentAction) -> Bool {
    [.autoObserve, .autoInvestigateReadOnly].contains(permission(for: action))
  }
}
