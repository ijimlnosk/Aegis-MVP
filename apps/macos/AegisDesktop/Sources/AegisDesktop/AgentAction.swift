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
  case captureScreen = "capture_screen"
  case inspectScreen = "inspect_screen"
  case inspectActiveWindow = "inspect_active_window"
  case inspectScreenWithProjectContext = "inspect_screen_with_project_context"
  case getScreenAwarenessStatus = "get_screen_awareness_status"
  case listVisibleWindows = "list_visible_windows"
  case inspectWindow = "inspect_window"
  case startDockerContainer = "start_docker_container"
  case stopDockerContainer = "stop_docker_container"
  case restartDockerContainer = "restart_docker_container"
  case answer
  case unknown

  static var plannable: [Self] { allCases.filter { $0 != .unknown } }
  var requiresApproval: Bool { ApprovalPolicy.requiresApproval(for: self) }
  var isDockerMutation: Bool {
    [.startDockerContainer, .stopDockerContainer, .restartDockerContainer].contains(self)
  }
  var isProjectAction: Bool {
    [.openProject, .getRememberedProjectStatus, .getProjectGitStatus, .getProjectBranch,
     .getProjectDiffSummary, .getProjectRecentCommits, .getProjectChangedFiles,
     .getProjectPackageScripts, .getProjectHealth, .assessProjectDeploymentReadiness, .runProjectTypecheck,
     .runProjectTests, .runProjectLint, .runProjectBuild, .startDevelopmentSession,
     .endDevelopmentSession, .getDevelopmentRecap].contains(self)
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
