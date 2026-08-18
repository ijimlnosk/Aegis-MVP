enum AgentAction: String, Codable, CaseIterable {
  case kakaoMessage = "kakao_message"
  case openApplication = "open_application"
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
  case startDockerContainer = "start_docker_container"
  case stopDockerContainer = "stop_docker_container"
  case restartDockerContainer = "restart_docker_container"
  case answer
  case unknown

  static var plannable: [Self] { allCases.filter { $0 != .unknown } }
  var requiresApproval: Bool {
    [.kakaoMessage, .openApplication, .closeApplication, .browserSearch, .setClipboard,
     .startDockerContainer, .stopDockerContainer, .restartDockerContainer].contains(self)
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
