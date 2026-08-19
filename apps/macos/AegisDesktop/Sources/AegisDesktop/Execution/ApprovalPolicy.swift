enum ActionRisk: String, Codable {
  case safeRead
  case safeValidation
  case localMutation
  case remoteMutation
  case destructive
}

enum ApprovalPolicy {
  static func risk(for action: AgentAction) -> ActionRisk {
    switch action {
    case .getActiveApplication, .getSystemStatus, .listRunningApplications, .getClipboard,
         .getServerStatus, .getDockerContainers, .getDockerLogs, .getServerProjectStatus,
         .getRememberedProjectStatus, .getProjectGitStatus, .getProjectBranch,
         .getProjectDiffSummary, .getProjectRecentCommits, .getProjectChangedFiles,
         .getProjectPackageScripts, .getProjectHealth, .assessProjectDeploymentReadiness,
         .getDevelopmentRecap, .getTodayDevelopmentSummary, .answer:
      .safeRead
    case .captureScreen, .inspectScreen, .inspectActiveWindow,
         .inspectScreenWithProjectContext, .getScreenAwarenessStatus,
         .listVisibleWindows, .inspectWindow:
      .safeRead
    case .runProjectTypecheck, .runProjectLint, .runProjectTests, .runProjectBuild,
         .startDevelopmentSession, .endDevelopmentSession:
      .safeValidation
    case .openApplication, .openProject, .closeApplication, .browserSearch, .setClipboard:
      .localMutation
    case .kakaoMessage, .startDockerContainer, .stopDockerContainer, .restartDockerContainer:
      .remoteMutation
    case .unknown: .destructive
    }
  }

  static func requiresApproval(for action: AgentAction) -> Bool {
    requiresApproval(for: risk(for: action))
  }

  static func requiresApproval(for risk: ActionRisk) -> Bool {
    [.localMutation, .remoteMutation, .destructive].contains(risk)
  }
}
