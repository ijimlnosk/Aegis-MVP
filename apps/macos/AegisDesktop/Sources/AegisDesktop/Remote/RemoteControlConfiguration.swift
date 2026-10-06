import Foundation

struct RemoteControlConfiguration: Equatable {
  let enabled: Bool
  let host: String
  let port: Int

  static func load(_ environment: [String: String] = RemoteEnvironment.load()) -> Self {
    Self(enabled: environment["AEGIS_REMOTE_ENABLED"] == "true",
         host: environment["AEGIS_REMOTE_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines)
           .nilIfEmpty ?? "127.0.0.1",
         port: Int(environment["AEGIS_REMOTE_PORT"] ?? "8790") ?? 8790)
  }

  var binding: String {
    if ["127.0.0.1", "::1", "localhost"].contains(host) { return "loopback" }
    let octets = host.split(separator: ".").compactMap { Int($0) }
    if octets.count == 4, octets[0] == 100, (64...127).contains(octets[1]) { return "Tailscale" }
    return "private/configured"
  }
}

struct DesktopBridgeConfiguration: Equatable {
  let enabled: Bool
  let host: String
  let port: UInt16
  let token: String

  static func load(_ supplied: [String: String]? = nil) -> Self {
    let environment = supplied ?? RemoteEnvironment.load()
    let configured = environment["AEGIS_DESKTOP_BRIDGE_TOKEN"]?.trimmed ?? ""
    let token = configured.isEmpty && supplied == nil ? DesktopBridgeSecretStore.loadOrCreate() : configured
    let requestedHost = environment["AEGIS_DESKTOP_BRIDGE_HOST"]?.trimmed ?? "127.0.0.1"
    let configuredPort = Int(environment["AEGIS_DESKTOP_BRIDGE_PORT"] ?? "8791") ?? 8791
    return Self(enabled: !token.isEmpty && environment["AEGIS_DESKTOP_BRIDGE_ENABLED"] != "false",
                host: requestedHost == "127.0.0.1" ? requestedHost : "127.0.0.1",
                port: UInt16(clamping: configuredPort), token: token)
  }
}

enum DesktopBridgeSecretStore {
  static var url: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/Aegis/desktop-bridge.token")
  }

  static func loadOrCreate() -> String {
    if let existing = try? String(contentsOf: url, encoding: .utf8).trimmed, existing.count >= 32 { return existing }
    var generator = SystemRandomNumberGenerator()
    let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(token.utf8).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      return token
    } catch { return "" }
  }
}

enum RemoteEnvironment {
  static func load() -> [String: String] {
    var values = ProcessInfo.processInfo.environment
    for url in candidates() {
      guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
      for line in text.split(whereSeparator: \.isNewline) {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        if parts.count == 2, values[parts[0]] == nil { values[parts[0]] = parts[1] }
      }
    }
    return values
  }

  static func candidates(bundleURL: URL = Bundle.main.bundleURL,
                         executableURL: URL? = Bundle.main.executableURL) -> [URL] {
    let support = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/Aegis/config.env")
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: ".env.local")
    var result = [support, current]
    // <repo>/apps/macos/AegisDesktop/.build/AegisDesktop.app for the signed bundle,
    // <repo>/apps/macos/AegisDesktop/.build/<triple>/debug/AegisDesktop for `swift run`.
    if bundleURL.pathExtension == "app" {
      result.append(ancestor(of: bundleURL, levels: 5).appending(path: ".env.local"))
    } else if let executableURL {
      result.append(ancestor(of: executableURL, levels: 7).appending(path: ".env.local"))
    }
    return result
  }

  private static func ancestor(of url: URL, levels: Int) -> URL {
    (0..<levels).reduce(url) { current, _ in current.deletingLastPathComponent() }
  }
}

private extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
