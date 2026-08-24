enum ActionRisk: String, Codable {
  case safeRead
  case safeNavigation
  case localInteraction
  case safeValidation
  case localMutation
  case remoteMutation
  case sensitiveInteraction
  case destructive
}

enum ApprovalPolicy {
  static func risk(for step: AgentStep) -> ActionRisk {
    guard [.setUIText, .appendUIText].contains(step.action) else { return risk(for: step.action) }
    let purpose = step.inputPurpose ?? .unknown
    guard purpose.isTrustedSemanticLabel(step.uiLabel) else { return .localMutation }
    return purpose.risk
  }

  static func requiresApproval(for step: AgentStep) -> Bool {
    requiresApproval(for: risk(for: step))
  }

  static func risk(for action: AgentAction) -> ActionRisk {
    switch action {
    case .getActiveApplication, .getSystemStatus, .listRunningApplications, .getClipboard,
         .getServerStatus, .getDockerContainers, .getDockerLogs, .getServerProjectStatus,
         .getRememberedProjectStatus, .findProjectPath, .getProjectGitStatus, .getProjectBranch,
         .getProjectDiffSummary, .getProjectRecentCommits, .getProjectChangedFiles,
         .getProjectPackageScripts, .getProjectHealth, .assessProjectDeploymentReadiness,
         .getDevelopmentRecap, .getTodayDevelopmentSummary, .getAIBackendStatus,
         .getRemoteControlStatus, .inspectGitDiff, .proposeCommitPlan,
         .getRemoteStatus, .proposePush, .getCIStatus, .getPullRequestStatus,
         .getGitWorkflowStatus, .answer:
      .safeRead
    case .getCodingAgentStatus, .getCodingAgentRecentDiagnostics,
      .analyzeProjectWithCodingAgent, .proposeCodingTask,
      .discoverDevelopmentTask, .rankDevelopmentCandidates, .proposeDevelopmentTask,
      .getAutonomousDevelopmentStatus,
         .reviewCodingTaskResult, .verifyCodingTask:
      .safeRead
    case .captureScreen, .inspectScreen, .inspectActiveWindow,
         .inspectScreenWithProjectContext, .getScreenAwarenessStatus,
         .listVisibleWindows, .inspectWindow:
      .safeRead
    case .getUIControlStatus, .getVSCodeQuickOpenStatus, .listUIElements, .inspectUIElement:
      .safeRead
    case .activateApplication, .focusWindow, .focusUIElement,
         .pressKeyboardShortcut, .scrollUI:
      .safeNavigation
    case .setUIText, .appendUIText, .pressUIElement, .selectMenuItem:
      .localInteraction
    case .closeWindow:
      .localMutation
    case .runProjectTypecheck, .runProjectLint, .runProjectTests, .runProjectBuild,
         .startDevelopmentSession, .endDevelopmentSession:
      .safeValidation
    case .openApplication, .openProject, .closeApplication, .browserSearch, .setClipboard:
      .localMutation
    case .executeCodingTask, .rollbackCodingTask, .executeDevelopmentTask, .repairDevelopmentTask,
         .createCommit:
      .localMutation
    case .verifyDevelopmentTask:
      .safeValidation
    case .kakaoMessage, .startDockerContainer, .stopDockerContainer, .restartDockerContainer,
         .pushCurrentBranch:
      .remoteMutation
    case .unknown: .destructive
    }
  }

  static func requiresApproval(for action: AgentAction) -> Bool {
    requiresApproval(for: risk(for: action))
  }

  static func requiresApproval(for risk: ActionRisk) -> Bool {
    [.localInteraction, .localMutation, .remoteMutation, .sensitiveInteraction,
     .destructive].contains(risk)
  }
}
