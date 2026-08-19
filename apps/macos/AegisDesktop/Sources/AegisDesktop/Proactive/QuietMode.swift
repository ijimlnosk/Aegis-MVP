import Foundation

enum QuietScope: Equatable { case all, server }
struct QuietMode: Equatable { let scope: QuietScope; let until: Date }

struct ProactiveStore {
  var quietMode: QuietMode?
  var lastEvent: ProactiveEvent?
  var suppressedTypes: Set<ProactiveEventType> = []

  func shouldSurface(_ event: ProactiveEvent, now: Date = .now) -> Bool {
    if suppressedTypes.contains(event.type) { return false }
    guard let quietMode, quietMode.until > now, event.severity != .critical else { return true }
    return quietMode.scope == .server && event.source != .server
  }
}
