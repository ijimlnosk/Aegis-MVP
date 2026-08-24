import Foundation
import Network

@MainActor
final class DesktopBridgeServer {
  private let configuration: DesktopBridgeConfiguration
  private var listener: NWListener?
  private var sessions: [String: DesktopBridgeSession] = [:]
  private(set) var status = "stopped"

  init(configuration: DesktopBridgeConfiguration = .load()) { self.configuration = configuration }

  func start() {
    guard configuration.enabled, listener == nil else {
      status = configuration.enabled ? status : "disabled"; return
    }
    guard configuration.host == "127.0.0.1", let port = NWEndpoint.Port(rawValue: configuration.port) else {
      status = "invalidConfiguration"; return
    }
    do {
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: port)
      let listener = try NWListener(using: parameters)
      listener.newConnectionHandler = { [weak self] connection in
        connection.start(queue: .global(qos: .userInitiated)); self?.receive(connection)
      }
      listener.stateUpdateHandler = { [weak self] state in Task { @MainActor in
        guard let self else { return }
        switch state {
        case .ready: self.status = "listening"
          print("Remote Desktop Bridge listening on 127.0.0.1:\(self.configuration.port)")
        case .failed: self.status = "failed"
        case .cancelled: self.status = "stopped"
        default: break
        }
      } }
      listener.start(queue: .global(qos: .utility)); self.listener = listener; status = "starting"
    } catch { status = "failed" }
  }

  func stop() { listener?.cancel(); listener = nil; sessions.removeAll(); status = "stopped" }

  private nonisolated func receive(_ connection: NWConnection, data: Data = Data()) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, complete, error in
      var accumulated = data; if let chunk { accumulated.append(chunk) }
      if let request = HTTPBridgeRequest(data: accumulated) {
        Task { @MainActor in
          guard let self else { return connection.cancel() }
          let response = await self.handle(request)
          connection.send(content: response.data, completion: .contentProcessed { _ in connection.cancel() })
        }
      } else if !complete, error == nil, accumulated.count < 65_536 {
        self?.receive(connection, data: accumulated)
      } else { connection.cancel() }
    }
  }

  private func handle(_ request: HTTPBridgeRequest) async -> HTTPBridgeResponse {
    guard DesktopBridgeAuthentication.matches(request.authorization, token: configuration.token) else {
      return .json(401, ["error": "unauthorized"])
    }
    if request.method == "GET", request.path == "/health" {
      return .encodable(200, DesktopBridgeHealth())
    }
    if request.method == "GET", request.path == "/v1/status" {
      return .json(200, ["status": "ok", "service": "AegisDesktopBridge"])
    }
    if request.method == "POST", request.path == "/v1/commands",
       let command: DesktopBridgeCommand = request.decode() {
      return .encodable(200, await session(command.sessionId).send(id: command.commandId, text: command.text))
    }
    let parts = request.path.split(separator: "/").map(String.init)
    if request.method == "POST", parts.count == 4, parts[0] == "v1", parts[1] == "approvals",
       ["approve", "reject"].contains(parts[3]), let body: DesktopBridgeApproval = request.decode(),
       let approvalID = UUID(uuidString: parts[2]) {
      return .encodable(200, await session(body.sessionId).approve(commandId: body.commandId,
        approvalId: approvalID, accepted: parts[3] == "approve"))
    }
    if request.method == "POST", parts.count == 4, parts[0] == "v1", parts[1] == "commands",
       parts[3] == "cancel",
       let body: DesktopBridgeApproval = request.decode() {
      return .encodable(200, session(body.sessionId).cancel(commandId: parts[2]))
    }
    if request.method == "POST", parts.count == 4, parts[0] == "v1", parts[1] == "commands",
       parts[3] == "status", let body: DesktopBridgeApproval = request.decode() {
      return .encodable(200, session(body.sessionId).progress(commandId: parts[2]))
    }
    return .json(404, ["error": "notFound"])
  }

  private func session(_ id: String) -> DesktopBridgeSession {
    if let existing = sessions[id] { return existing }
    let created = DesktopBridgeSession(sessionID: id); sessions[id] = created; return created
  }

}

enum DesktopBridgeAuthentication {
  static func matches(_ authorization: String, token: String) -> Bool {
    let left = Array(authorization.utf8), right = Array("Bearer \(token)".utf8)
    guard left.count == right.count else { return false }
    return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
  }
}

struct HTTPBridgeRequest {
  let method: String; let path: String; let authorization: String; let body: Data
  init?(data: Data) {
    guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
          let header = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { return nil }
    let lines = header.components(separatedBy: "\r\n"), first = lines.first?.split(separator: " ") ?? []
    guard first.count >= 2 else { return nil }
    let headers = Dictionary(uniqueKeysWithValues: lines.dropFirst().compactMap { line -> (String, String)? in
      guard let index = line.firstIndex(of: ":") else { return nil }
      return (String(line[..<index]).lowercased(), line[line.index(after: index)...].trimmingCharacters(in: .whitespaces))
    })
    let length = Int(headers["content-length"] ?? "0") ?? 0
    let start = boundary.upperBound; guard data.count >= start + length else { return nil }
    method = String(first[0]); path = String(first[1]); authorization = headers["authorization"] ?? ""
    body = data.subdata(in: start..<(start + length))
  }
  func decode<T: Decodable>() -> T? { try? JSONDecoder().decode(T.self, from: body) }
}

struct HTTPBridgeResponse {
  let status: Int; let body: Data
  var data: Data {
    let reason = status == 200 ? "OK" : status == 401 ? "Unauthorized" : "Not Found"
    let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
    return Data(header.utf8) + body
  }
  static func json(_ status: Int, _ value: [String: String]) -> Self {
    Self(status: status, body: (try? JSONSerialization.data(withJSONObject: value)) ?? Data())
  }
  static func encodable<T: Encodable>(_ status: Int, _ value: T) -> Self {
    Self(status: status, body: (try? JSONEncoder().encode(value)) ?? Data())
  }
}
