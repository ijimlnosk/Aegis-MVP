import Foundation

enum RemoteControlDiagnostics {
  static func report(configuration: RemoteControlConfiguration = .load(),
                     bridge: DesktopBridgeConfiguration = .load([:]),
                     desktopBridgeStatus: String = "unknown") async -> String {
    let bridgeLine = "- desktop bridge: \(bridge.host):\(bridge.port) · \(desktopBridgeStatus)"
    guard configuration.enabled else {
      return """
      원격 제어 상태
      - enabled: false
      - gateway: disabled
      - bind: \(configuration.binding)
      - port: \(configuration.port)
      - active sessions: 0
      - pending approvals: 0
      \(bridgeLine)
      """
    }
    let reachable = await probe(host: configuration.host, port: configuration.port)
    return """
    원격 제어 상태
    - enabled: true
    - gateway: \(reachable ? "reachable" : "unavailable")
    - bind: \(configuration.binding)
    - port: \(configuration.port)
    - sessions/approvals: 게이트웨이 인증 진단에서 확인
    \(bridgeLine)
    """
  }

  private static func probe(host: String, port: Int) async -> Bool {
    guard let url = URL(string: "http://\(host):\(port)/") else { return false }
    var request = URLRequest(url: url); request.timeoutInterval = 1
    do { let (_, response) = try await URLSession.shared.data(for: request)
      return (response as? HTTPURLResponse)?.statusCode == 200
    } catch { return false }
  }
}
