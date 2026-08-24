import Foundation

enum VisionBackend: String, Sendable { case local, remote, fallback, unavailable }

enum VisionBackendAvailability: String, Sendable {
  case available, serverUnavailable, modelUnavailable, timeout, invalidConfiguration
}

enum VisionFailureCategory: String, Sendable {
  case serverUnavailable, modelUnavailable, timeout, invalidConfiguration
  case malformedResponse, httpFailure, cancelled, memoryPressure
}

struct VisionEndpoint: Equatable, Sendable {
  let baseURL: URL
  var chatURL: URL { baseURL.appending(path: "api/chat") }
  var tagsURL: URL { baseURL.appending(path: "api/tags") }
  var host: String { baseURL.host ?? "unknown" }
  var port: Int { baseURL.port ?? (baseURL.scheme == "https" ? 443 : 80) }
  var isLoopback: Bool { ["127.0.0.1", "localhost", "::1"].contains(host.lowercased()) }
}

enum ScreenAnalysisConfiguration {
  static func normalEndpoint(environment: [String: String] = developmentEnvironment()) -> VisionEndpoint? {
    environment["AEGIS_OLLAMA_URL"].flatMap(endpoint)
  }

  static func normalModel(environment: [String: String] = developmentEnvironment()) -> String {
    environment["OLLAMA_MODEL"] ?? "qwen3:8b"
  }

  static func normalTimeout(environment: [String: String] = developmentEnvironment()) -> TimeInterval {
    bounded(environment["AEGIS_OLLAMA_REMOTE_TIMEOUT_SECONDS"], default: 300)
  }

  static func visionEndpoint(environment: [String: String] = developmentEnvironment()) -> VisionEndpoint? {
    environment["AEGIS_VISION_OLLAMA_URL"].flatMap(endpoint)
  }

  static func backend(environment: [String: String] = developmentEnvironment()) -> VisionBackend {
    guard let vision = visionEndpoint(environment: environment) else { return .unavailable }
    return vision.isLoopback ? .local : .remote
  }

  static func model(environment: [String: String] = developmentEnvironment()) -> String {
    environment["AEGIS_VISION_MODEL"] ?? "qwen2.5vl:7b"
  }

  static func localFallback(environment: [String: String] = developmentEnvironment()) -> Bool {
    environment["AEGIS_VISION_LOCAL_FALLBACK"]?.lowercased() == "true"
  }

  static func timeout(environment: [String: String] = developmentEnvironment()) -> TimeInterval {
    parsedTimeout(environment: environment)
  }

  static func remoteTimeout(environment: [String: String] = developmentEnvironment()) -> TimeInterval {
    parsedRemoteTimeout(environment: environment)
  }

  static func resourceProfile() -> VisionResourceProfile {
    guard let raw = value("AEGIS_VISION_RESOURCE_PROFILE"),
      let profile = VisionResourceProfile(rawValue: raw) else { return .balanced }
    return profile
  }

  static func maximumLongEdge(for profile: VisionResourceProfile) -> Int {
    let raw = value("AEGIS_VISION_MAX_LONG_EDGE") ?? value("AEGIS_VISION_MAX_IMAGE_DIMENSION")
    guard let raw, let value = Int(raw), value >= 640, value <= 2_560 else {
      return profile.defaultLongEdge
    }
    return value
  }

  static func maximumPixels() -> Int {
    guard let raw = value("AEGIS_VISION_MAX_PIXELS"), let value = Int(raw),
      value >= 500_000, value <= 8_000_000 else { return 1_500_000 }
    return value
  }

  static func jpegQuality(for profile: VisionResourceProfile) -> Double {
    guard let raw = value("AEGIS_VISION_JPEG_QUALITY"), let value = Double(raw),
      value >= 0.35, value <= 0.95 else { return profile.defaultJPEGQuality }
    return value
  }

  static func keepAliveSeconds() -> Int {
    guard let raw = value("AEGIS_VISION_KEEP_ALIVE_SECONDS"), let value = Int(raw),
      value >= 0, value <= 600 else { return 60 }
    return value
  }

  static func maximumWindows() -> Int {
    guard let raw = value("AEGIS_VISION_MAX_WINDOWS"), let value = Int(raw),
      value >= 1, value <= 4 else { return 2 }
    return value
  }

  static func parsedTimeout(environment: [String: String]) -> TimeInterval {
    bounded(environment["AEGIS_VISION_TIMEOUT_SECONDS"], default: 120)
  }

  static func parsedRemoteTimeout(environment: [String: String]) -> TimeInterval {
    bounded(environment["AEGIS_VISION_REMOTE_TIMEOUT_SECONDS"], default: 300)
  }

  static func parsedNormalTimeout(environment: [String: String]) -> TimeInterval {
    bounded(environment["AEGIS_OLLAMA_REMOTE_TIMEOUT_SECONDS"], default: 300)
  }

  static func parsedLongEdge(environment: [String: String],
                             profile: VisionResourceProfile = .balanced) -> Int {
    guard let raw = environment["AEGIS_VISION_MAX_LONG_EDGE"], let value = Int(raw),
      value >= 640, value <= 2_560 else { return profile.defaultLongEdge }
    return value
  }

  private static func endpoint(_ raw: String) -> VisionEndpoint? {
    guard let components = URLComponents(string: raw),
      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
      let host = components.host, !host.isEmpty,
      components.user == nil, components.password == nil,
      components.query == nil, components.fragment == nil,
      components.path.isEmpty || components.path == "/",
      let url = components.url else { return nil }
    if let port = components.port, !(1...65_535).contains(port) { return nil }
    return VisionEndpoint(baseURL: url)
  }

  private static func bounded(_ raw: String?, default fallback: TimeInterval) -> TimeInterval {
    guard let raw, let value = Double(raw), value >= 10, value <= 600 else { return fallback }
    return value
  }

  private static func value(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key] ?? developmentEnvironment()[key]
  }

  private static func developmentEnvironment() -> [String: String] {
    let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let candidates = [root.appending(path: ".env.local"),
      URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: ".env.local")]
    guard let text = candidates.compactMap({ try? String(contentsOf: $0, encoding: .utf8) }).first else { return [:] }
    return text.split(separator: "\n").reduce(into: [:]) { values, line in
      let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
      if parts.count == 2, !parts[0].hasPrefix("#") { values[parts[0]] = parts[1] }
    }
  }
}
