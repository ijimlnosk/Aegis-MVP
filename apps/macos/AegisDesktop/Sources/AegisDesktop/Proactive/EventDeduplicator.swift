import Foundation

struct EventDeduplicator {
  let cooldown: TimeInterval
  private(set) var active: [String: ProactiveSeverity] = [:]
  private var lastEmitted: [String: Date] = [:]
  init(cooldown: TimeInterval = 15 * 60) { self.cooldown = cooldown }

  mutating func accepts(_ event: ProactiveEvent, now: Date = .now) -> Bool {
    let key = event.deduplicationKey
    if event.isRecovery {
      guard active.removeValue(forKey: key) != nil else { return false }
      lastEmitted.removeValue(forKey: key)
      return true
    }
    if active[key] == event.severity { return false }
    if let last = lastEmitted[key], now.timeIntervalSince(last) < cooldown,
       active[key] != nil, event.severity <= active[key]! { return false }
    active[key] = event.severity; lastEmitted[key] = now
    return true
  }
}
