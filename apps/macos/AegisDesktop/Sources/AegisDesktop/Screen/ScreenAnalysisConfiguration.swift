import Foundation

enum ScreenAnalysisConfiguration {
  static let endpoint = URL(string: "http://127.0.0.1:11434/api/chat")!

  static func model() -> String {
    value("AEGIS_VISION_MODEL") ?? "qwen2.5vl:7b"
  }

  static func timeout() -> TimeInterval {
    guard let raw = value("AEGIS_VISION_TIMEOUT_SECONDS"), let value = Double(raw),
      value >= 10, value <= 600 else { return 120 }
    return value
  }

  static func resourceProfile() -> VisionResourceProfile {
    guard let raw = value("AEGIS_VISION_RESOURCE_PROFILE"),
      let profile = VisionResourceProfile(rawValue: raw) else { return .balanced }
    return profile
  }

  static func maximumLongEdge(for profile: VisionResourceProfile) -> Int {
    let raw = value("AEGIS_VISION_MAX_LONG_EDGE")
      ?? value("AEGIS_VISION_MAX_IMAGE_DIMENSION")
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
    guard let raw = environment["AEGIS_VISION_TIMEOUT_SECONDS"], let value = Double(raw),
      value >= 10, value <= 600 else { return 120 }
    return value
  }

  static func parsedLongEdge(environment: [String: String],
                             profile: VisionResourceProfile = .balanced) -> Int {
    guard let raw = environment["AEGIS_VISION_MAX_LONG_EDGE"], let value = Int(raw),
      value >= 640, value <= 2_560 else { return profile.defaultLongEdge }
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
