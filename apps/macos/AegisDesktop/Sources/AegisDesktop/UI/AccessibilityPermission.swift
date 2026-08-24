import ApplicationServices
import Foundation

enum AccessibilityAvailability: String, Codable, Sendable {
  case available, permissionRequired, unavailable, failed
}

enum AccessibilityPermission {
  static func status(prompt: Bool = false) -> AccessibilityAvailability {
    if AXIsProcessTrusted() { return .available }
    if prompt {
      let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
      _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    return .permissionRequired
  }
}
