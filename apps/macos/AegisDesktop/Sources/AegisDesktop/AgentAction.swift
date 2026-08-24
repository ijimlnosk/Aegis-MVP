enum AgentAction: String, Codable, CaseIterable {
  case kakaoMessage = "kakao_message"
  case openApplication = "open_application"
  case openProject = "open_project"
  case closeApplication = "close_application"
  case browserSearch = "browser_search"
  case getActiveApplication = "get_active_application"
  case getSystemStatus = "get_system_status"
  case listRunningApplications = "list_running_applications"
  case getClipboard = "get_clipboard"
  case setClipboard = "set_clipboard"
  case getServerStatus = "get_server_status"
  case getDockerContainers = "get_docker_containers"
  case getDockerLogs = "get_docker_logs"
  case getServerProjectStatus = "get_server_project_status"
  case getRememberedProjectStatus = "get_remembered_project_status"
  case findProjectPath = "find_project_path"
  case getProjectGitStatus = "get_project_git_status"
  case getProjectBranch = "get_project_branch"
  case getProjectDiffSummary = "get_project_diff_summary"
  case getProjectRecentCommits = "get_project_recent_commits"
  case getProjectChangedFiles = "get_project_changed_files"
  case getProjectPackageScripts = "get_project_package_scripts"
  case getProjectHealth = "get_project_health"
  case assessProjectDeploymentReadiness = "assess_project_deployment_readiness"
  case runProjectTypecheck = "run_project_typecheck"
  case runProjectTests = "run_project_tests"
  case runProjectLint = "run_project_lint"
  case runProjectBuild = "run_project_build"
  case startDevelopmentSession = "start_development_session"
  case endDevelopmentSession = "end_development_session"
  case getDevelopmentRecap = "get_development_recap"
  case getTodayDevelopmentSummary = "get_today_development_summary"
  case getCodingAgentStatus = "get_coding_agent_status"
  case getCodingAgentRecentDiagnostics = "get_coding_agent_recent_diagnostics"
  case analyzeProjectWithCodingAgent = "analyze_project_with_coding_agent"
  case proposeCodingTask = "propose_coding_task"
  case executeCodingTask = "execute_coding_task"
  case reviewCodingTaskResult = "review_coding_task_result"
  case verifyCodingTask = "verify_coding_task"
  case rollbackCodingTask = "rollback_coding_task"
  case discoverDevelopmentTask = "discover_development_task"
  case rankDevelopmentCandidates = "rank_development_candidates"
  case proposeDevelopmentTask = "propose_development_task"
  case executeDevelopmentTask = "execute_development_task"
  case verifyDevelopmentTask = "verify_development_task"
  case repairDevelopmentTask = "repair_development_task"
  case getAutonomousDevelopmentStatus = "get_autonomous_development_status"
  case inspectGitDiff = "inspect_git_diff"
  case proposeCommitPlan = "propose_commit_plan"
  case createCommit = "create_commit"
  case getRemoteStatus = "get_remote_status"
  case proposePush = "propose_push"
  case pushCurrentBranch = "push_current_branch"
  case getCIStatus = "get_ci_status"
  case getPullRequestStatus = "get_pull_request_status"
  case getGitWorkflowStatus = "get_git_workflow_status"
  case captureScreen = "capture_screen"
  case inspectScreen = "inspect_screen"
  case inspectActiveWindow = "inspect_active_window"
  case inspectScreenWithProjectContext = "inspect_screen_with_project_context"
  case getScreenAwarenessStatus = "get_screen_awareness_status"
  case getAIBackendStatus = "get_ai_backend_status"
  case getRemoteControlStatus = "get_remote_control_status"
  case listVisibleWindows = "list_visible_windows"
  case inspectWindow = "inspect_window"
  case getUIControlStatus = "get_ui_control_status"
  case getVSCodeQuickOpenStatus = "get_vscode_quick_open_status"
  case activateApplication = "activate_application"
  case focusWindow = "focus_window"
  case closeWindow = "close_window"
  case listUIElements = "list_ui_elements"
  case inspectUIElement = "inspect_ui_element"
  case pressUIElement = "press_ui_element"
  case focusUIElement = "focus_ui_element"
  case setUIText = "set_ui_text"
  case appendUIText = "append_ui_text"
  case pressKeyboardShortcut = "press_keyboard_shortcut"
  case scrollUI = "scroll_ui"
  case selectMenuItem = "select_menu_item"
  case startDockerContainer = "start_docker_container"
  case stopDockerContainer = "stop_docker_container"
  case restartDockerContainer = "restart_docker_container"
  case answer
  case unknown

  static var plannable: [Self] { allCases.filter { $0 != .unknown } }
  var requiresApproval: Bool { ApprovalPolicy.requiresApproval(for: self) }
  var isUIAction: Bool {
    [.getUIControlStatus, .getVSCodeQuickOpenStatus, .activateApplication, .focusWindow,
     .closeWindow, .listUIElements, .inspectUIElement, .pressUIElement, .focusUIElement,
     .setUIText, .appendUIText, .pressKeyboardShortcut, .scrollUI, .selectMenuItem]
      .contains(self)
  }
  var isDockerMutation: Bool {
    [.startDockerContainer, .stopDockerContainer, .restartDockerContainer].contains(self)
  }
  var isProjectAction: Bool {
    [.openProject, .getRememberedProjectStatus, .getProjectGitStatus, .getProjectBranch,
     .getProjectDiffSummary, .getProjectRecentCommits, .getProjectChangedFiles,
     .getProjectPackageScripts, .getProjectHealth, .assessProjectDeploymentReadiness, .runProjectTypecheck,
     .runProjectTests, .runProjectLint, .runProjectBuild, .startDevelopmentSession,
     .endDevelopmentSession, .getDevelopmentRecap].contains(self)
      || [.getCodingAgentRecentDiagnostics, .analyzeProjectWithCodingAgent, .proposeCodingTask, .executeCodingTask,
          .reviewCodingTaskResult, .verifyCodingTask, .rollbackCodingTask,
          .discoverDevelopmentTask, .rankDevelopmentCandidates, .proposeDevelopmentTask,
          .executeDevelopmentTask, .verifyDevelopmentTask, .repairDevelopmentTask,
          .getAutonomousDevelopmentStatus].contains(self)
      || [.inspectGitDiff, .proposeCommitPlan, .createCommit, .getRemoteStatus,
          .proposePush, .pushCurrentBranch, .getCIStatus, .getPullRequestStatus,
          .getGitWorkflowStatus].contains(self)
  }

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .unknown
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
