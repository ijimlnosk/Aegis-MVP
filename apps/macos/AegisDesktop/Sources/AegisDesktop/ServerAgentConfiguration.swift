import Foundation

struct ServerAgentConfiguration: Decodable {
  let url: String
  let token: String

  static func load() throws -> Self {
    let environment = ProcessInfo.processInfo.environment
    let stored = loadJSON()
    let development = loadDevelopmentEnvironment()
    let url = environment["SERVER_AGENT_URL"] ?? stored?.url
      ?? development["SERVER_AGENT_URL"] ?? "http://100.74.88.48:8787"
    let token = environment["SERVER_AGENT_TOKEN"] ?? stored?.token
      ?? development["SERVER_AGENT_TOKEN"]
    guard let token, !token.isEmpty else { throw ServerAgentError.missingToken }
    return Self(url: url, token: token)
  }

  private static func loadJSON() -> Self? {
    let file = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: ".config/aegis/server-agent.json")
    guard let data = try? Data(contentsOf: file) else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }

  private static func loadDevelopmentEnvironment() -> [String: String] {
    let root = Bundle.main.bundleURL
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appending(path: ".env.local"), encoding: .utf8) else {
      return [:]
    }
    return text.split(separator: "\n").reduce(into: [:]) { values, line in
      let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
      if parts.count == 2, !parts[0].hasPrefix("#") { values[parts[0]] = parts[1] }
    }
  }
}

enum ServerAgentError: LocalizedError {
  case missingToken, invalidURL, invalidToken, offline, networkUnavailable, server(String), invalidResponse

  var errorDescription: String? {
    switch self {
    case .missingToken: "SERVER_AGENT_TOKEN 설정이 없습니다."
    case .invalidURL: "Server Agent URL 설정이 올바르지 않습니다."
    case .invalidToken: "Server Agent 토큰이 올바르지 않습니다."
    case .offline: "Server Agent가 응답하지 않습니다. 서버 실행 상태를 확인하세요."
    case .networkUnavailable: "Tailscale 또는 네트워크 연결을 확인하세요."
    case .server(let message): message
    case .invalidResponse: "Server Agent 응답 형식이 올바르지 않습니다."
    }
  }
}
