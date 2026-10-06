import Foundation
import IOKit.pwr_mgt

/// Prevents idle system sleep while remote control is enabled so the phone can still reach Aegis.
/// The display may still sleep and lock; closing a laptop lid without an external display still sleeps.
@MainActor
final class RemoteKeepAwake {
  private var assertion: IOPMAssertionID?

  nonisolated static func isEnabled(_ environment: [String: String]) -> Bool {
    let remote = environment["AEGIS_REMOTE_ENABLED"] == "true"
    return (environment["AEGIS_REMOTE_KEEP_AWAKE"] ?? (remote ? "true" : "false")) == "true"
  }

  func start(environment: [String: String] = RemoteEnvironment.load()) {
    guard assertion == nil, Self.isEnabled(environment) else { return }
    var id = IOPMAssertionID(0)
    let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn), "Aegis 원격 제어 대기" as CFString, &id)
    if result == kIOReturnSuccess { assertion = id }
  }

  func stop() {
    guard let assertion else { return }
    IOPMAssertionRelease(assertion)
    self.assertion = nil
  }

  var isActive: Bool { assertion != nil }
}
