import Foundation

enum ServerTool: String {
  case status, containers, logs, projectStatus, start, stop, restart

  var path: String {
    switch self {
    case .status: "/v1/tools/system-status"
    case .containers: "/v1/tools/docker-containers"
    case .logs: "/v1/tools/docker-logs"
    case .projectStatus: "/v1/tools/project-status"
    case .start, .stop, .restart: "/v1/tools/docker-\(rawValue)"
    }
  }

  var requiresApproval: Bool { [.start, .stop, .restart].contains(self) }
}

enum ServerAgentClient {
  static func call(_ tool: ServerTool, arguments: [String: Any] = [:]) async throws -> String {
    let config = try ServerAgentConfiguration.load()
    guard let base = URL(string: config.url), let url = URL(string: tool.path, relativeTo: base) else {
      throw ServerAgentError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 10
    request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: arguments)
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw ServerAgentError.invalidResponse }
      if http.statusCode == 401 { throw ServerAgentError.invalidToken }
      let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      guard (200..<300).contains(http.statusCode) else {
        throw ServerAgentError.server(body?["error"] as? String ?? "Server Agent 요청에 실패했습니다.")
      }
      return format(tool, body: body)
    } catch let error as ServerAgentError { throw error }
    catch let error as URLError {
      switch error.code {
      case .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed: throw ServerAgentError.networkUnavailable
      default: throw ServerAgentError.offline
      }
    }
  }

  private static func format(_ tool: ServerTool, body: [String: Any]?) -> String {
    if tool == .status {
      let uptime = body?["uptime"] as? String ?? "알 수 없음"
      let memory = body?["memory"] as? String ?? "알 수 없음"
      let disk = body?["disk"] as? String ?? "알 수 없음"
      let docker = body?["docker"] as? String ?? "없음"
      // Machine readers (context observer, Docker inventory) parse this raw layout;
      // ServerResultFormatter builds the chat view from it.
      return "sol-server\nUptime: \(uptime)\nMemory:\n\(memory)\nDisk:\n\(disk)\nDocker:\n\(docker)"
    }
    return body?["output"] as? String ?? "작업을 완료했습니다."
  }
}
